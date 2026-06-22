#!/usr/bin/env bash
# claude-continue-watcher (tmux)
#
# Watches every tmux pane for a transient Claude Code API error banner
# ("API Error: ... temporarily limiting requests", "529 Overloaded", ...) and,
# when an idle Claude session is showing such an error, sends "continue" +
# Enter. Re-checks every INTERVAL seconds so it keeps retrying until the API
# recovers.
#
# A pane is acted on ONLY when ALL hold (in the live tail, last TAIL_LINES):
#   1. Claude UI chrome present  ("shift+tab to cycle" / "? for shortcuts")
#      -> proves it's an interactive Claude session, never a bare shell, a
#         pager, or a `tail -f` of this very log (self-feedback guard).
#   2. NOT busy                  ("esc to interrupt" absent)
#   3. The literal "API Error:" banner present
#   4. A transient keyword present (retry-able errors only)
#
# Kill switch / opt-out:
#   - touch $PAUSE_FILE        -> pause (keeps looping, sends nothing)
#   - SKIP_PATTERN='regex'     -> never touch sessions whose name matches
#   - DRY_RUN=1                -> log intended sends without sending
#
# Usage:
#   ./watcher-tmux.sh
#   DRY_RUN=1 ./watcher-tmux.sh
#   SKIP_PATTERN='^prod|deploy' INTERVAL=15 ./watcher-tmux.sh

set -uo pipefail

INTERVAL="${INTERVAL:-15}"
DRY_RUN="${DRY_RUN:-0}"
TAIL_LINES="${TAIL_LINES:-30}"
PAUSE_FILE="${PAUSE_FILE:-$HOME/.claude/claude-watcher.pause}"
SKIP_PATTERN="${SKIP_PATTERN:-}"
TRANSIENT='temporarily limiting requests|Overloaded|overloaded_error|Error: 529|server-side issue'
CLAUDE_UI='shift\+tab to cycle|for shortcuts|⏵⏵|Context.*Usage'

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

command -v tmux >/dev/null 2>&1 || { echo "tmux not found"; exit 1; }

log "claude-continue-watcher started (tmux, interval=${INTERVAL}s, tail=${TAIL_LINES}, dry_run=${DRY_RUN}, pause_file=${PAUSE_FILE})"
while true; do
  if [ -f "$PAUSE_FILE" ]; then sleep "$INTERVAL"; continue; fi
  if tmux has-session 2>/dev/null; then
    while IFS= read -r pane; do
      [ -z "$pane" ] && continue
      sess="${pane%%:*}"
      if [ -n "$SKIP_PATTERN" ] && printf '%s' "$sess" | grep -qE "$SKIP_PATTERN"; then continue; fi
      tail_txt="$(tmux capture-pane -p -t "$pane" 2>/dev/null | tail -n "$TAIL_LINES")" || continue
      printf '%s\n' "$tail_txt" | grep -qE "$CLAUDE_UI" || continue   # 1. real Claude session
      printf '%s\n' "$tail_txt" | grep -q 'esc to interrupt' && continue   # 2. busy -> skip
      printf '%s\n' "$tail_txt" | grep -q 'API Error:' || continue         # 3. banner
      printf '%s\n' "$tail_txt" | grep -qE "$TRANSIENT" || continue        # 4. transient only
      if [ "$DRY_RUN" = "0" ]; then
        tmux send-keys -t "$pane" "continue" Enter
        log "transient API error detected -> sent 'continue' to pane $pane"
      else
        log "[DRY_RUN] would send 'continue' to pane $pane"
      fi
    done < <(tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}')
  fi
  sleep "$INTERVAL"
done
