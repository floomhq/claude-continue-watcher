#!/usr/bin/env bash
# Installer for claude-continue-watcher.
#
#   macOS  -> iTerm2 watcher, kept alive by launchd
#   Linux  -> tmux watcher, kept alive by a systemd --user service (or nohup)
#
# Idempotent: re-running re-installs and restarts cleanly.
# Env: INTERVAL (default 15s).  Use DRY_RUN=1 ./install.sh to install paused.

set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
INTERVAL="${INTERVAL:-15}"
BIN_DIR="$HOME/.local/bin"
LOG="$HOME/.claude/logs/claude-continue-watcher.log"
mkdir -p "$BIN_DIR" "$HOME/.claude/logs"

case "$(uname -s)" in
  Darwin)
    install -m755 "$DIR/watcher-iterm.sh" "$BIN_DIR/claude-continue-watcher.sh"
    PLIST="$HOME/Library/LaunchAgents/sh.skills.claude-continue-watcher.plist"
    sed -e "s|__SCRIPT__|$BIN_DIR/claude-continue-watcher.sh|g" \
        -e "s|__LOG__|$LOG|g" \
        -e "s|__INTERVAL__|$INTERVAL|g" \
        "$DIR/templates/launchd.plist.tmpl" > "$PLIST"
    launchctl unload "$PLIST" 2>/dev/null || true
    launchctl load "$PLIST"
    echo "Installed (macOS/iTerm2). launchd label: sh.skills.claude-continue-watcher"
    echo "First run may prompt: 'bash wants to control iTerm' -> approve under"
    echo "System Settings > Privacy & Security > Automation."
    ;;
  Linux)
    command -v tmux >/dev/null 2>&1 || { echo "tmux is required on Linux"; exit 1; }
    install -m755 "$DIR/watcher-tmux.sh" "$BIN_DIR/claude-continue-watcher.sh"
    if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
      UDIR="$HOME/.config/systemd/user"; mkdir -p "$UDIR"
      sed -e "s|__SCRIPT__|$BIN_DIR/claude-continue-watcher.sh|g" \
          -e "s|__INTERVAL__|$INTERVAL|g" \
          "$DIR/templates/systemd.service.tmpl" > "$UDIR/claude-continue-watcher.service"
      systemctl --user daemon-reload
      systemctl --user enable --now claude-continue-watcher.service
      echo "Installed (Linux/tmux). Manage: systemctl --user {status|stop} claude-continue-watcher"
    else
      pkill -f "$BIN_DIR/claude-continue-watcher.sh" 2>/dev/null || true
      INTERVAL="$INTERVAL" nohup "$BIN_DIR/claude-continue-watcher.sh" >>"$LOG" 2>&1 &
      echo "Installed (Linux/tmux, nohup fallback). PID $!. Log: $LOG"
    fi
    ;;
  *)
    echo "Unsupported OS. Run watcher-tmux.sh or watcher-iterm.sh manually."; exit 1 ;;
esac

echo "Log: $LOG"
echo "Pause:  touch $HOME/.claude/claude-watcher.pause"
echo "Resume: rm    $HOME/.claude/claude-watcher.pause"
