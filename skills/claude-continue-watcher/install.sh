#!/usr/bin/env bash
# Installer for claude-continue-watcher.
#
# Picks a watcher backend, then a service manager to keep it alive:
#
#   tmux backend   -> works on Linux, macOS, and Windows (WSL).
#                     Run your Claude Code sessions inside tmux.
#   iTerm2 backend -> macOS only, no tmux needed.
#
# Backend selection (override with WATCHER=tmux|iterm):
#   - tmux  if a tmux server is running (any OS)
#   - iterm if macOS and no tmux server
#   - tmux  if Linux/WSL with tmux installed
#
# Service manager: launchd on macOS, systemd --user on Linux (nohup fallback).
# Idempotent: re-running re-installs and restarts cleanly.
# Env: INTERVAL (integer seconds, default 15).
# To pause after install: touch ~/.claude/claude-watcher.pause

set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
INTERVAL="${INTERVAL:-15}"
BIN_DIR="$HOME/.local/bin"
LOG="$HOME/.claude/logs/claude-continue-watcher.log"
OS="$(uname -s)"
mkdir -p "$BIN_DIR" "$HOME/.claude/logs"

# --- choose backend ---------------------------------------------------------
MODE="${WATCHER:-}"
if [ -z "$MODE" ]; then
  if command -v tmux >/dev/null 2>&1 && tmux has-session 2>/dev/null; then
    MODE=tmux
  elif [ "$OS" = "Darwin" ]; then
    MODE=iterm
  elif command -v tmux >/dev/null 2>&1; then
    MODE=tmux
  else
    echo "No supported backend found."
    echo "Install tmux and run your Claude Code sessions inside it (Linux/macOS/WSL),"
    echo "or use iTerm2 on macOS. Then re-run this installer."
    exit 1
  fi
fi

case "$MODE" in
  tmux)
    command -v tmux >/dev/null 2>&1 || { echo "WATCHER=tmux but tmux is not installed"; exit 1; }
    install -m755 "$DIR/watcher-tmux.sh" "$BIN_DIR/claude-continue-watcher.sh" ;;
  iterm)
    [ "$OS" = "Darwin" ] || { echo "WATCHER=iterm is macOS-only"; exit 1; }
    install -m755 "$DIR/watcher-macos.sh" "$BIN_DIR/claude-continue-watcher.sh" ;;
  *)
    echo "Unknown WATCHER='$MODE' (use tmux or iterm)"; exit 1 ;;
esac
echo "Backend: $MODE"

# --- choose service manager -------------------------------------------------
if [ "$OS" = "Darwin" ]; then
  PLIST="$HOME/Library/LaunchAgents/sh.skills.claude-continue-watcher.plist"
  sed -e "s|__SCRIPT__|$BIN_DIR/claude-continue-watcher.sh|g" \
      -e "s|__LOG__|$LOG|g" \
      -e "s|__INTERVAL__|$INTERVAL|g" \
      "$DIR/templates/launchd.plist.tmpl" > "$PLIST"
  launchctl unload "$PLIST" 2>/dev/null || true
  launchctl load "$PLIST"
  echo "Installed via launchd (label: sh.skills.claude-continue-watcher)."
  if [ "$MODE" = "iterm" ]; then
    echo "First run may prompt: 'bash wants to control iTerm' -> approve under"
    echo "System Settings > Privacy & Security > Automation."
  fi
elif command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
  UDIR="$HOME/.config/systemd/user"; mkdir -p "$UDIR"
  sed -e "s|__SCRIPT__|$BIN_DIR/claude-continue-watcher.sh|g" \
      -e "s|__INTERVAL__|$INTERVAL|g" \
      "$DIR/templates/systemd.service.tmpl" > "$UDIR/claude-continue-watcher.service"
  systemctl --user daemon-reload
  systemctl --user enable --now claude-continue-watcher.service
  echo "Installed via systemd --user. Manage: systemctl --user {status|stop} claude-continue-watcher"
else
  pkill -f "$BIN_DIR/claude-continue-watcher.sh" 2>/dev/null || true
  INTERVAL="$INTERVAL" nohup "$BIN_DIR/claude-continue-watcher.sh" >>"$LOG" 2>&1 &
  echo "Installed via nohup (PID $!)."
fi

echo "Log:    $LOG"
echo "Pause:  touch $HOME/.claude/claude-watcher.pause"
echo "Resume: rm    $HOME/.claude/claude-watcher.pause"
