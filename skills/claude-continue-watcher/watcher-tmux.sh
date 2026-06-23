#!/usr/bin/env bash
# claude-continue-watcher (tmux)
#
# Watches every tmux pane for a stalled Claude Code session and sends
# "continue" + Enter to resume it. Two triggers, two cadences:
#
#   1. Transient API error  (every INTERVAL secs, default 15)
#      idle banner "API Error: ..." + a transient keyword
#      (temporarily limiting requests / Overloaded / 529 / ...).
#
#   2. Usage limit  (every USAGE_INTERVAL secs, default 600 = 10 min)
#      the 5-hour / weekly cap banner: "You've hit your ... limit ... resets".
#      Polled slowly; a "continue" lands the moment the window resets.
#
# A pane is acted on ONLY when it's a real, idle Claude session (live tail):
#   - Claude UI chrome present  (footer "shift+tab to cycle" / "Context..Usage"
#     / "⏵⏵" / "for agents" / "context used")
#   - NOT busy ("esc to interrupt" absent)
#
# Kill switch / opt-out:
#   - touch $PAUSE_FILE        -> pause (keeps looping, sends nothing)
#   - SKIP_PATTERN='regex'     -> never touch sessions whose name matches
#   - DRY_RUN=1                -> log intended sends without sending

set -uo pipefail
# systemd/cron may not export HOME; derive it safely before using it.
: "${HOME:=$(cd ~ 2>/dev/null && pwd || echo /root)}"

INTERVAL="${INTERVAL:-15}"
USAGE_INTERVAL="${USAGE_INTERVAL:-600}"
DRY_RUN="${DRY_RUN:-0}"
TAIL_LINES="${TAIL_LINES:-30}"
PAUSE_FILE="${PAUSE_FILE:-$HOME/.claude/claude-watcher.pause}"
SKIP_PATTERN="${SKIP_PATTERN:-}"
TRANSIENT='temporarily limiting requests|Overloaded|overloaded_error|Error: 529|server-side issue'
CLAUDE_UI='shift\+tab to cycle|for shortcuts|⏵⏵|for agents|context used|Context.*Usage'

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

command -v tmux >/dev/null 2>&1 || { echo "tmux not found"; exit 1; }

last_usage=0
DO_USAGE=0
log "claude-continue-watcher started (tmux, interval=${INTERVAL}s, usage_interval=${USAGE_INTERVAL}s, tail=${TAIL_LINES}, dry_run=${DRY_RUN}, pause_file=${PAUSE_FILE})"
while true; do
  if [ -f "$PAUSE_FILE" ]; then sleep "$INTERVAL"; continue; fi
  now="$(date +%s)"
  DO_USAGE=0
  if [ "$(( now - last_usage ))" -ge "$USAGE_INTERVAL" ]; then DO_USAGE=1; last_usage="$now"; fi
  if tmux has-session 2>/dev/null; then
    while IFS= read -r pane; do
      [ -z "$pane" ] && continue
      sess="${pane%%:*}"
      if [ -n "$SKIP_PATTERN" ] && printf '%s' "$sess" | grep -qE "$SKIP_PATTERN"; then continue; fi
      t="$(tmux capture-pane -p -t "$pane" 2>/dev/null | tail -n "$TAIL_LINES")" || continue
      printf '%s\n' "$t" | grep -qE "$CLAUDE_UI" || continue            # real Claude session
      printf '%s\n' "$t" | grep -q 'esc to interrupt' && continue       # busy -> skip
      reason=""
      if printf '%s\n' "$t" | grep -q 'API Error:' && printf '%s\n' "$t" | grep -qE "$TRANSIENT"; then
        reason="transient API error"
      elif [ "$DO_USAGE" = "1" ] && printf '%s\n' "$t" | grep -q 'hit your' \
           && printf '%s\n' "$t" | grep -q 'limit' && printf '%s\n' "$t" | grep -q 'resets'; then
        reason="usage limit"
      fi
      [ -z "$reason" ] && continue
      if [ "$DRY_RUN" = "0" ]; then
        tmux send-keys -t "$pane" "continue" Enter
        log "$reason detected -> sent 'continue' to pane $pane"
      else
        log "[DRY_RUN] would send 'continue' to pane $pane ($reason)"
      fi
    done < <(tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}')
  fi
  sleep "$INTERVAL"
done
