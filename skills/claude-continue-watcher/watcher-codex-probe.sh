#!/usr/bin/env bash
# watcher-codex-probe.sh  (tmux, LOG-ONLY)
#
# Observation-only probe for Codex CLI sessions. It NEVER sends keystrokes.
# When a Codex session shows error-ish text, it records the full live tail to
# a log so we can learn the exact transient-error banner and confirm whether
# typing "continue" is the right recovery (vs Codex auto-retrying / a hard
# usage limit) BEFORE enabling any live sender.
#
# Codex session gate: the model/effort/dir footer, e.g. "gpt-5.5 high · ~/dir".
#
# Env: INTERVAL (default 15), CODEX_LOG (default below).

set -uo pipefail
: "${HOME:=$(cd ~ 2>/dev/null && pwd || echo /root)}"

INTERVAL="${INTERVAL:-15}"
TAIL_LINES="${TAIL_LINES:-30}"
LOG="${CODEX_LOG:-/var/log/claude-continue-watcher-codex.log}"

CODEX_UI='(gpt-[0-9]|o[0-9] |codex)[^·]* · '
ERR='stream error|stream disconnected|error sending request|rate.?limit|too many requests|usage limit|try again|service unavailable|overloaded|reconnect|We.re experiencing|high demand|429|5[0-9][0-9] '
BUSY='[Ee]sc to interrupt|to interrupt'

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }

command -v tmux >/dev/null 2>&1 || { echo "tmux not found"; exit 1; }

declare -A SEEN
log "codex-error-probe started (LOG-ONLY, interval=${INTERVAL}s)"
while true; do
  if tmux has-session 2>/dev/null; then
    while IFS= read -r pane; do
      [ -z "$pane" ] && continue
      t="$(tmux capture-pane -p -t "$pane" 2>/dev/null | tail -n "$TAIL_LINES")" || continue
      printf '%s\n' "$t" | grep -qE "$CODEX_UI" || continue       # Codex session only
      printf '%s\n' "$t" | grep -qiE "$ERR" || continue           # some error vocab present
      h="$(printf '%s' "$t" | cksum | awk '{print $1}')"          # dedup identical state per pane
      [ "${SEEN[$pane]:-}" = "$h" ] && continue
      SEEN[$pane]="$h"
      busy=no; printf '%s\n' "$t" | grep -qE "$BUSY" && busy=yes
      log "===== CODEX error-ish in $pane (busy=$busy) ====="
      printf '%s\n' "$t" | sed 's/^/    /' >> "$LOG"
      log "===== end $pane ====="
    done < <(tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}')
  fi
  sleep "$INTERVAL"
done
