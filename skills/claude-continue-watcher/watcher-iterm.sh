#!/usr/bin/env bash
# claude-continue-watcher (macOS / iTerm2)
#
# Watches every iTerm2 session for a transient Claude Code API error banner
# ("API Error: ... temporarily limiting requests", "529 Overloaded", ...) and,
# when an idle Claude session is showing such an error, types "continue" and
# presses Return. Re-checks every INTERVAL seconds so it keeps retrying until
# the API recovers.
#
# A session is acted on ONLY when ALL hold (in the live tail, last TAIL_LINES):
#   1. Claude UI chrome present  ("shift+tab to cycle" / "? for shortcuts")
#      -> proves it's an interactive Claude session, never a bare shell, a
#         pager, or a `tail -f` of this very log (self-feedback guard).
#   2. NOT busy                  ("esc to interrupt" absent)
#   3. The literal "API Error:" banner present
#   4. A transient keyword present (retry-able errors only)
#
# Kill switch:
#   - touch $PAUSE_FILE  -> pause (keeps looping, sends nothing)
#   - DRY_RUN=1          -> log intended sends without sending
#
# Requires: iTerm2. First run triggers a one-time macOS Automation consent
# prompt ("bash wants to control iTerm") -> approve it.
#
# Usage:
#   ./watcher-iterm.sh
#   DRY_RUN=1 ./watcher-iterm.sh
#   INTERVAL=15 TAIL_LINES=40 ./watcher-iterm.sh

set -uo pipefail

INTERVAL="${INTERVAL:-15}"
DRY_RUN="${DRY_RUN:-0}"
TAIL_LINES="${TAIL_LINES:-30}"
PAUSE_FILE="${PAUSE_FILE:-$HOME/.claude/claude-watcher.pause}"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

scan_and_continue() {
  osascript <<OSA
tell application "iTerm2"
  set acted to ""
  repeat with w in windows
    repeat with t in tabs of w
      repeat with s in sessions of t
        set txt to ""
        try
          set txt to contents of s
        end try
        set para to paragraphs of txt
        set cnt to (count of para)
        set startIdx to cnt - $TAIL_LINES
        if startIdx < 1 then set startIdx to 1
        set tailTxt to ""
        repeat with i from startIdx to cnt
          set tailTxt to tailTxt & (item i of para) & linefeed
        end repeat
        set isClaude to (tailTxt contains "shift+tab to cycle") or (tailTxt contains "for shortcuts") or (tailTxt contains "⏵⏵") or ((tailTxt contains "Context") and (tailTxt contains "Usage"))
        set hasBanner to (tailTxt contains "API Error:")
        set isTransient to (tailTxt contains "temporarily limiting requests") or (tailTxt contains "Overloaded") or (tailTxt contains "overloaded_error") or (tailTxt contains "Error: 529") or (tailTxt contains "server-side issue")
        set isBusy to (tailTxt contains "esc to interrupt")
        if isClaude and hasBanner and isTransient and (not isBusy) then
          if "$DRY_RUN" is "0" then
            tell s to write text "continue"
          end if
          set acted to acted & (id of s) & linefeed
        end if
      end repeat
    end repeat
  end repeat
  return acted
end tell
OSA
}

log "claude-continue-watcher started (iTerm2, interval=${INTERVAL}s, tail=${TAIL_LINES}, dry_run=${DRY_RUN}, pause_file=${PAUSE_FILE})"
while true; do
  if [ -f "$PAUSE_FILE" ]; then sleep "$INTERVAL"; continue; fi
  out="$(scan_and_continue 2>/dev/null)"
  if [ -n "${out//[$'\n ']/}" ]; then
    while IFS= read -r sid; do
      [ -z "$sid" ] && continue
      if [ "$DRY_RUN" = "0" ]; then
        log "transient API error detected -> sent 'continue' to iTerm session $sid"
      else
        log "[DRY_RUN] would send 'continue' to iTerm session $sid"
      fi
    done <<< "$out"
  fi
  sleep "$INTERVAL"
done
