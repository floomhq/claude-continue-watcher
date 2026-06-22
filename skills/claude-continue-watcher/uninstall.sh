#!/usr/bin/env bash
set -uo pipefail
BIN="$HOME/.local/bin/claude-continue-watcher.sh"
case "$(uname -s)" in
  Darwin)
    PLIST="$HOME/Library/LaunchAgents/sh.skills.claude-continue-watcher.plist"
    launchctl unload "$PLIST" 2>/dev/null || true
    rm -f "$PLIST"
    ;;
  Linux)
    systemctl --user disable --now claude-continue-watcher.service 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/claude-continue-watcher.service"
    systemctl --user daemon-reload 2>/dev/null || true
    pkill -f "$BIN" 2>/dev/null || true
    ;;
esac
rm -f "$BIN"
echo "claude-continue-watcher uninstalled."
