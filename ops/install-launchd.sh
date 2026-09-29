#!/bin/zsh
# Run as an admin on macmini64: sudo zsh /Users/agentictrader/ai-day-trading-experiment/ops/install-launchd.sh
# Installs system LaunchDaemons that run as agentictrader (no GUI login needed; survives reboot).
set -e
for old in research trade review; do launchctl bootout system/com.ag3nt.trader.$old 2>/dev/null || true; rm -f /Library/LaunchDaemons/com.ag3nt.trader.$old.plist; done
for f in /Users/agentictrader/ai-day-trading-experiment/ops/launchd/*.plist; do
  dest=/Library/LaunchDaemons/${f:t}
  launchctl bootout system/${${f:t}%.plist} 2>/dev/null || true
  cp "$f" "$dest"; chown root:wheel "$dest"; chmod 644 "$dest"
  launchctl bootstrap system "$dest"
  echo "loaded ${f:t}"
done
