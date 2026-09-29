# AI Day Trading Experiment

An autonomous AI agent (Claude Code, running headless on a schedule) that researches and
trades a small Robinhood **cash** account through Robinhood's agentic MCP server. The thesis
is aggressive and narrow: buy high-risk, high-upside small caps that sit on the bottlenecks
of the AI build-out: optical interconnect, memory, power equipment, packaging, materials.

> [!WARNING]
> **Experimental. Not financial advice.** This is a personal experiment that trades real
> money, deliberately with an aggressive risk profile and money the owner can afford to lose
> entirely. Nothing here is a recommendation to buy or sell anything. The agent can and
> will make bad trades; LLMs misread data and state wrong facts confidently. The safeguards
> below reduce specific risks. They are **not** a guarantee: a stop-loss order can fill far
> below its price on a gap, and a denylist is never complete. If you run this, you are
> responsible for every order it places. Read the code, start in `plan` mode, and use only
> money you are fully prepared to lose.

## How it works

```
launchd (every 5 min) → ops/tick.sh → ops/run.sh <phase> → claude -p (Robinhood MCP + web)
                                                        ↘ PreToolUse hook: .claude/hooks/order-guard.sh
```

- **Phases** (weekdays, US Central time; `ops/schedule.default`):
  - `research` at 07:15: open-ended research, updates the thesis, writes the day's plan. It **cannot** place orders.
  - `trade` at 08:45: executes the plan, 15 min after the open.
  - `review` at 14:00: exits, stops and journal.
  - `check` runs: a run can book up to 4 extra same-day runs (08:35–14:50) in
    `ops/requests/<date>.txt`. The scheduler enforces the limits, not the agent.
- **Memory:** `kb/` (thesis, watchlist, positions, lessons, daily journal) is the agent's
  memory across runs. It is git-ignored here, because it contains account data.
- **Prompts:** `ops/prompts/`. The standing rules are in `CLAUDE.md`.

## Safety design

The core property is that **the account cannot go negative.**

- **Cash account only, no margin.** In a cash account the worst case for any long
  position is zero, and that includes leveraged and inverse ETFs, which the agent may buy.
  Short selling, options, crypto, and margin and options-upgrade tools are all refused.
- **Enforced mechanically, not just in prompts.** `order-guard.sh` runs before every
  Robinhood and Gmail tool call and blocks:
  - any account except the configured one
  - forbidden tools
  - any order while `ops/MODE` is `plan`
  - any order during the research phase
  - email to anyone except the owner, with no cc, bcc or attachments, and no inbox reads
- **The guard fails closed.** If `ops/config.local` is missing, or the hook input can't be
  parsed, the call is blocked.
- **Broker-side stops.** Every fill gets a GTC stop sell at Robinhood, so exits happen even
  if the host is down.
- **Settled cash only.** Proceeds from a sale settle T+1, so the agent gets roughly one
  round trip per day with the full balance. That's by design.
- **Web content is treated as data, never as instructions,** to limit prompt injection from
  pages that try to steer the agent into a ticker.
- **Bounded cost.** At most 7 runs per weekday, each with a hard time cap.

## Setup (macOS)

1. Create a dedicated **non-admin** macOS user for the agent. Install Claude Code for it
   and add the MCP server:
   `claude mcp add --transport http --scope user robinhood-trading https://agent.robinhood.com/mcp/trading`,
   then authenticate it with `/mcp`.
2. Copy this repo into that user's home. Then `cp ops/config.example ops/config.local` and
   fill in your cash account number (the one with `agentic_allowed=true`) and your email.
3. Keep `ops/MODE` at `plan` (the default). Run `zsh ops/run.sh research` by hand and read
   what it writes to `kb/`.
4. Install the scheduler as an admin:
   `sudo zsh /Users/<agent-user>/ai-day-trading-experiment/ops/install-launchd.sh`.
5. Once you trust the plans it writes, `echo live > ops/MODE`.

**Paths:** `ops/launchd/*.plist` and `ops/install-launchd.sh` assume the agent user is
`agentictrader` with the repo at `~/ai-day-trading-experiment`. Edit them if yours differ.

**FileVault:** with FileVault on, nothing runs after a reboot until the disk is unlocked at
the login screen. The failure is safe: missed runs, not bad trades.

## License

MIT. See [LICENSE](LICENSE). Provided as is, with no warranty. See the disclaimer above.
