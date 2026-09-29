#!/bin/zsh
# Scheduler tick, run by launchd every 5 min. Fires fixed runs (ops/schedule.default) and
# agent-requested runs (ops/requests/YYYY-MM-DD.txt, lines "HH:MM phase reason...").
# Limits on requested runs are enforced here, not trusted to the agent.
set -u
ROOT=${0:A:h:h}; cd "$ROOT" || exit 1
TODAY=$(date +%F); NOW=${TICK_NOW:-$(date +%H:%M)}; DOW=${TICK_DOW:-$(date +%u)}   # TICK_* = test overrides; 1=Mon..7=Sun
DONE=ops/state/$TODAY.done; touch "$DONE"
(( DOW > 5 )) && exit 0

tomin() { print $(( 10#${1%%:*} * 60 + 10#${1##*:} )) }
now=$(tomin $NOW)
STALE=30          # a run more than 30 min overdue (e.g. mac was asleep) is skipped
REQ_MIN=$(tomin 08:35) REQ_MAX=$(tomin 14:50) REQ_CAP=4

due=()
while read -r t p _; do
  [[ -z "$t" || "$t" == \#* ]] && continue
  due+=("$t $p fixed")
done < ops/schedule.default

n=0
if [[ -f ops/requests/$TODAY.txt ]]; then
  while read -r t p reason; do
    [[ -z "$t" || "$t" == \#* ]] && continue
    [[ "$t" =~ '^[0-2][0-9]:[0-5][0-9]$' ]] || continue
    [[ "$p" == trade || "$p" == check ]] || continue
    m=$(tomin $t); (( m < REQ_MIN || m > REQ_MAX )) && continue
    (( ++n > REQ_CAP )) && break
    due+=("$t $p requested")
  done < ops/requests/$TODAY.txt
fi

for entry in "${due[@]}"; do
  t=${entry%% *}; rest=${entry#* }; p=${rest%% *}
  key="$t $p"; m=$(tomin $t)
  grep -qxF "$key" "$DONE" && continue
  (( m > now )) && continue
  if (( now - m > STALE )); then print "$key" >> "$DONE"; print "$(date "+%F %T") tick skipped stale $key" >> ops/logs/runs.log; continue; fi
  [[ -d ops/.run.lock ]] && continue          # a run is in progress; retry next tick
  [[ -z ${TICK_DRY:-} ]] && print "$key" >> "$DONE"   # dry runs must not consume real slots
  [[ -z ${TICK_DRY:-} ]] && print "$(date "+%F %T") tick firing $key (${rest#* })" >> ops/logs/runs.log
  if [[ -n ${TICK_DRY:-} ]]; then print "WOULD LAUNCH $key"; else zsh ops/run.sh "$p" >> ops/logs/tick.out 2>&1; fi   # synchronous: a backgrounded run was killed when tick exited (2026-09-28); launchd skips ticks while this runs
  break                                       # one launch per tick
done
