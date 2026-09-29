#!/bin/zsh
# Headless trading run. Invoked by launchd: ops/run.sh <research|trade|review>
set -u
PHASE=${1:?usage: run.sh research|trade|review}
ROOT=${0:A:h:h}
cd "$ROOT" || exit 1
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/bin:/bin"
export RUN_PHASE=$PHASE
source ops/config.local || { print -u2 "run.sh: ops/config.local missing (copy ops/config.example)"; exit 1; }
mkdir -p ops/logs kb/journal
print "$(date "+%F %T") $PHASE started pid=$$" >> ops/logs/runs.log

TS=$(date +%Y-%m-%d_%H%M)
LOG="ops/logs/$TS-$PHASE.log"
# All phases on Fable 5.1 (owner's choice, 2026-09-27). Research gets a longer cap (07:15 start,
# must end before the 08:45 trade run).
MODEL=claude-fable-5-1
if [[ $PHASE == research ]]; then MAX_SECONDS=4500; else MAX_SECONDS=2700; fi   # 75 / 45 min

# One run at a time; a stale lock older than the longest cap is broken.
LOCK=ops/.run.lock
if ! mkdir "$LOCK" 2>/dev/null; then
  if [[ -n $(find "$LOCK" -maxdepth 0 -mmin +80 2>/dev/null) ]]; then rm -rf "$LOCK"; mkdir "$LOCK"
  else print "$(date) another run holds the lock; skipping $PHASE" >> ops/logs/skipped.log; exit 0; fi
fi
trap 'rm -rf "$LOCK"' EXIT

PROMPT="$(cat ops/prompts/common.md)

$(cat ops/prompts/$PHASE.md)

Current local time: $(date '+%A %Y-%m-%d %H:%M %Z'). Trading mode (ops/MODE): $(cat ops/MODE 2>/dev/null || print plan).
TRADER_ACCOUNT=$TRADER_ACCOUNT  TRADER_OWNER_EMAIL=$TRADER_OWNER_EMAIL"

{
  print "=== $PHASE run $(date) model=$MODEL mode=$(cat ops/MODE 2>/dev/null || print plan) ==="
  claude -p "$PROMPT" --model $MODEL --max-turns 250 --permission-mode acceptEdits &
  pid=$!
  ( sleep $MAX_SECONDS; kill $pid 2>/dev/null && print "!!! killed after ${MAX_SECONDS}s" ) &
  watchdog=$!
  wait $pid; rc=$?
  kill $watchdog 2>/dev/null
  print "=== exit $rc $(date) ==="
} > "$LOG" 2>&1

print "$(date '+%F %T') $PHASE rc=$rc log=$LOG" >> ops/logs/runs.log

# Snapshot the knowledge base so the thesis's evolution is diffable. Local repo, no remote.
git add -A kb >/dev/null 2>&1 && git -c user.name=agentictrader -c user.email=agentictrader@macmini64.local \
  commit -qm "kb: $PHASE $TS (rc=$rc)" >/dev/null 2>&1 || true
