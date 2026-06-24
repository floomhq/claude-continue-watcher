#!/usr/bin/env bash
# claude-continue-watcher (tmux) — simple proven detection
set -uo pipefail
: "${HOME:=$(cd ~ 2>/dev/null && pwd || echo /root)}"
INTERVAL="${INTERVAL:-15}"
USAGE_INTERVAL="${USAGE_INTERVAL:-600}"
DRY_RUN="${DRY_RUN:-0}"
TAIL_LINES="${TAIL_LINES:-30}"
PAUSE_FILE="${PAUSE_FILE:-$HOME/.claude/claude-watcher.pause}"
SKIP_PATTERN="${SKIP_PATTERN:-}"
CLAUDE_UI='shift\+tab to cycle|⏵⏵|for agents|context used|Context.*Usage'
TRANSIENT='temporarily limiting requests|Overloaded|overloaded_error|Error: 529|server-side issue|Rate limited'

# Opt-in anonymous counter (off unless CCW_TELEMETRY=1). Sends only a count + a
# random anonymous install id to the global tally — no hostname, no content.
CCW_TELEMETRY="${CCW_TELEMETRY:-0}"
CCW_ENDPOINT="${CCW_ENDPOINT:-https://ccw.openpaper.dev/ping}"
CCW_ID_FILE="$HOME/.claude/ccw-id"
if [ "$CCW_TELEMETRY" = "1" ] && [ ! -f "$CCW_ID_FILE" ]; then
  (uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || date +%s%N) | tr 'A-Z' 'a-z' > "$CCW_ID_FILE" 2>/dev/null || true
fi
CCW_ID="$(cat "$CCW_ID_FILE" 2>/dev/null || echo anon)"
ccw_ping() { [ "$CCW_TELEMETRY" = "1" ] && [ "${1:-0}" -gt 0 ] && curl -s -m 5 -X POST "$CCW_ENDPOINT" -H 'Content-Type: application/json' -d "{\"id\":\"$CCW_ID\",\"n\":$1}" >/dev/null 2>&1 & }

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
command -v tmux >/dev/null 2>&1 || { echo "tmux not found"; exit 1; }
last_usage=0; DO_USAGE=0
log "claude-continue-watcher started (tmux, interval=${INTERVAL}s, usage_interval=${USAGE_INTERVAL}s, dry_run=${DRY_RUN}, pause_file=${PAUSE_FILE})"
while true; do
  if [ -f "$PAUSE_FILE" ]; then sleep "$INTERVAL"; continue; fi
  now="$(date +%s)"; DO_USAGE=0
  if [ "$(( now - last_usage ))" -ge "$USAGE_INTERVAL" ]; then DO_USAGE=1; last_usage="$now"; fi
  cycle_sent=0
  if tmux has-session 2>/dev/null; then
    while IFS= read -r pane; do
      [ -z "$pane" ] && continue
      sess="${pane%%:*}"
      if [ -n "$SKIP_PATTERN" ] && printf '%s' "$sess" | grep -qE "$SKIP_PATTERN"; then continue; fi
      t="$(tmux capture-pane -p -t "$pane" 2>/dev/null | tail -n "$TAIL_LINES")" || continue
      printf '%s\n' "$t" | grep -qE "$CLAUDE_UI" || continue
      printf '%s\n' "$t" | grep -q 'esc to interrupt' && continue
      reason=""
      if printf '%s\n' "$t" | grep -q 'API Error:' && printf '%s\n' "$t" | grep -qE "$TRANSIENT"; then reason="transient"
      elif [ "$DO_USAGE" = "1" ] && printf '%s\n' "$t" | grep -q 'hit your' && printf '%s\n' "$t" | grep -q 'limit' && printf '%s\n' "$t" | grep -q 'resets'; then reason="usage"; fi
      [ -z "$reason" ] && continue
      if [ "$DRY_RUN" = "0" ]; then tmux send-keys -t "$pane" "continue" Enter; log "$reason -> sent 'continue' to pane $pane"; cycle_sent=$((cycle_sent+1)); else log "[DRY_RUN] $pane ($reason)"; fi
    done < <(tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}')
  fi
  ccw_ping "$cycle_sent"
  sleep "$INTERVAL"
done
