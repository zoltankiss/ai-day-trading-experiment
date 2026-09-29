#!/bin/zsh
# PreToolUse guard for every mcp__robinhood-trading__* call.
# Mechanical enforcement of the CLAUDE.md red line — the agent's judgment is not trusted
# for these. Exit 2 = block (stderr is shown to the model). Fail closed on bad input.

DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
# Account + owner email come from the git-ignored ops/config.local (see ops/config.example).
[[ -r "$DIR/ops/config.local" ]] && source "$DIR/ops/config.local"
AGENTIC_ACCOUNT="${TRADER_ACCOUNT:-}"
OWNER_EMAIL="${TRADER_OWNER_EMAIL:-}"
LOG="$DIR/ops/logs/guard.jsonl"
mkdir -p "$DIR/ops/logs"

input=$(cat)
tool=$(print -r -- "$input" | jq -r '.tool_name // empty' 2>/dev/null)
[[ -z "$AGENTIC_ACCOUNT" || -z "$OWNER_EMAIL" ]] && { print -u2 "order-guard: ops/config.local missing TRADER_ACCOUNT/TRADER_OWNER_EMAIL — blocking"; exit 2; }
[[ -z "$tool" ]] && { print -u2 "order-guard: unparseable hook input — blocking"; exit 2; }
short=${tool#mcp__robinhood-trading__}
acct=$(print -r -- "$input" | jq -r '.tool_input.account_number // empty')
mode=$(cat "$DIR/ops/MODE" 2>/dev/null || print plan)   # plan | live; missing file = plan
phase=${RUN_PHASE:-interactive}

block() {
  jq -nc --arg t "$short" --arg r "$1" --argjson i "$(print -r -- "$input" | jq '.tool_input')" \
    '{ts: (now|todate), decision: "block", tool: $t, reason: $r, input: $i}' >> "$LOG"
  print -u2 "order-guard BLOCKED $short: $1"
  exit 2
}

# 0. Gmail: the only use is emailing the owner the run summary. Block every other Gmail tool
#    (no inbox reads) and any recipient other than the owner — a prompt-injected web page must
#    not be able to turn the agent into an exfiltration channel.
if [[ "$tool" == mcp__claude_ai_Gmail__* ]]; then
  [[ "$tool" != mcp__claude_ai_Gmail__send_message ]] && block "only Gmail send_message is allowed"
  ok=$(print -r -- "$input" | jq -r --arg e "$OWNER_EMAIL" '.tool_input | ((.to // []) == [$e])
        and ((.cc // []) | length == 0) and ((.bcc // []) | length == 0)
        and (.draftId == null) and ((.attachments // []) | length == 0)')
  [[ "$ok" != true ]] && block "email may only go to $OWNER_EMAIL (no cc/bcc/drafts/attachments)"
  exit 0
fi

# 1. Tools that are never allowed: options, crypto, margin/options upgrades.
case "$short" in
  place_option_order|review_option_order|exercise_option|cancel_option_exercise|\
  place_crypto_order|preview_crypto_order|cancel_crypto_order|\
  get_limited_margin_upgrade_info|get_option_level_upgrade_info)
    block "forbidden tool (options/crypto/margin-upgrade) — see CLAUDE.md red line" ;;
esac

# 2. Only the cash account, ever. Applies to reads too: there is no reason to touch any other account.
if [[ -n "$acct" && "$acct" != "$AGENTIC_ACCOUNT" ]]; then
  block "account $acct is not the agentic cash account $AGENTIC_ACCOUNT"
fi

# 3. Order-mutating tools.
case "$short" in
  place_equity_order|review_equity_order|cancel_equity_order)
    [[ "$short" != cancel_equity_order && "$acct" != "$AGENTIC_ACCOUNT" ]] && \
      block "account_number must be exactly $AGENTIC_ACCOUNT"
    side=$(print -r -- "$input" | jq -r '.tool_input.side // empty')
    [[ "$short" != cancel_equity_order && "$side" != buy && "$side" != sell ]] && \
      block "side must be buy or sell (got '$side')"
    # A sell in a cash account cannot open a short (broker rejects selling unowned shares);
    # this hook cannot see positions, so the broker is the backstop for over-selling.
    if [[ "$short" != review_equity_order ]]; then
      [[ "$mode" != live ]] && block "ops/MODE is '$mode' — orders disabled (plan-only)"
      [[ "$phase" == research ]] && block "research phase never places or cancels orders"
    fi
    jq -nc --arg t "$short" --arg m "$mode" --arg p "$phase" \
      --argjson i "$(print -r -- "$input" | jq '.tool_input')" \
      '{ts: (now|todate), decision: "allow", tool: $t, mode: $m, phase: $p, input: $i}' >> "$LOG"
    ;;
esac

exit 0
