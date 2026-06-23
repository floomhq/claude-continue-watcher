#!/usr/bin/env bash
# claude-continue-watcher.sh  (macOS / iTerm2 + Terminal.app)
#
# Simple, proven detection: if a Claude session shows the "API Error:" banner
# with a transient keyword and is not actively interruptible, type "continue".
# Also handles the 5h/weekly usage cap on a 10-min cadence.
#
#   touch $PAUSE_FILE   -> pause
#   DRY_RUN=1           -> log instead of send

set -uo pipefail
: "${HOME:=$(cd ~ 2>/dev/null && pwd || echo /tmp)}"

INTERVAL="${INTERVAL:-15}"
USAGE_INTERVAL="${USAGE_INTERVAL:-600}"
DRY_RUN="${DRY_RUN:-0}"
TAIL_LINES="${TAIL_LINES:-30}"
PAUSE_FILE="${PAUSE_FILE:-$HOME/.claude/claude-watcher.pause}"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

scan_iterm() {
  osascript <<OSA 2>/dev/null
if not (application "iTerm2" is running) then return ""
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
        set tl to ""
        repeat with i from startIdx to cnt
          set tl to tl & (item i of para) & linefeed
        end repeat
        set isClaude to (tl contains "shift+tab to cycle") or (tl contains "⏵⏵") or (tl contains "for agents") or (tl contains "context used") or ((tl contains "Context") and (tl contains "Usage"))
        set isTransient to (tl contains "API Error:") and ((tl contains "temporarily limiting requests") or (tl contains "Overloaded") or (tl contains "overloaded_error") or (tl contains "Error: 529") or (tl contains "server-side issue") or (tl contains "Rate limited"))
        set isUsage to (tl contains "hit your") and (tl contains "limit") and (tl contains "resets")
        set isBusy to (tl contains "esc to interrupt")
        if isClaude and (not isBusy) and (isTransient or (("$DO_USAGE" is "1") and isUsage)) then
          if "$DRY_RUN" is "0" then
            tell s to write text "continue"
          end if
          set acted to acted & "iterm" & linefeed
        end if
      end repeat
    end repeat
  end repeat
  return acted
end tell
OSA
}

scan_terminal() {
  osascript <<OSA 2>/dev/null
if not (application "Terminal" is running) then return ""
tell application "Terminal"
  set acted to ""
  repeat with wi from 1 to (count of windows)
    set w to window wi
    repeat with ti from 1 to (count of tabs of w)
      set txt to ""
      try
        set txt to (contents of tab ti of w)
      end try
      set para to paragraphs of txt
      set cnt to (count of para)
      set startIdx to cnt - $TAIL_LINES
      if startIdx < 1 then set startIdx to 1
      set tl to ""
      repeat with i from startIdx to cnt
        set tl to tl & (item i of para) & linefeed
      end repeat
      set isClaude to (tl contains "shift+tab to cycle") or (tl contains "⏵⏵") or (tl contains "for agents") or (tl contains "context used") or ((tl contains "Context") and (tl contains "Usage"))
      set isTransient to (tl contains "API Error:") and ((tl contains "temporarily limiting requests") or (tl contains "Overloaded") or (tl contains "overloaded_error") or (tl contains "Error: 529") or (tl contains "server-side issue") or (tl contains "Rate limited"))
      set isUsage to (tl contains "hit your") and (tl contains "limit") and (tl contains "resets")
      set isBusy to (tl contains "esc to interrupt")
      if isClaude and (not isBusy) and (isTransient or (("$DO_USAGE" is "1") and isUsage)) then
        if "$DRY_RUN" is "0" then
          do script "continue" in tab ti of w
        end if
        set acted to acted & "terminal " & wi & "." & ti & linefeed
      end if
    end repeat
  end repeat
  return acted
end tell
OSA
}

report() {
  [ -z "${1//[$'\n ']/}" ] && return 0
  while IFS= read -r tgt; do
    [ -z "$tgt" ] && continue
    if [ "$DRY_RUN" = "0" ]; then log "sent 'continue' to $tgt"; else log "[DRY_RUN] would send to $tgt"; fi
  done <<< "$1"
}

last_usage=0; DO_USAGE=0
log "claude-continue-watcher started (iTerm2 + Terminal.app, interval=${INTERVAL}s, usage_interval=${USAGE_INTERVAL}s, dry_run=${DRY_RUN})"
while true; do
  if [ -f "$PAUSE_FILE" ]; then sleep "$INTERVAL"; continue; fi
  now="$(date +%s)"; DO_USAGE=0
  if [ "$(( now - last_usage ))" -ge "$USAGE_INTERVAL" ]; then DO_USAGE=1; last_usage="$now"; fi
  report "$(scan_iterm)"
  report "$(scan_terminal)"
  sleep "$INTERVAL"
done
