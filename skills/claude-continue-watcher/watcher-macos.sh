#!/usr/bin/env bash
# claude-continue-watcher.sh  (macOS / iTerm2 + Terminal.app)
#
# Watches every iTerm2 AND Apple Terminal session for a transient Claude Code
# API error banner ("API Error: ... temporarily limiting requests", "529
# Overloaded", ...) and, when an idle Claude session is showing such an error,
# types "continue" and presses Return. Re-checks every INTERVAL seconds.
#
# A session is acted on ONLY when ALL hold (in the live tail, last TAIL_LINES):
#   1. Claude UI chrome present  (footer "shift+tab to cycle" / "Context..Usage")
#   2. NOT busy                  ("esc to interrupt" absent)
#   3. The literal "API Error:" banner present
#   4. A transient keyword present (retry-able errors only)
#
# Kill switch:
#   - touch $PAUSE_FILE  -> watcher pauses (keeps looping, sends nothing)
#   - DRY_RUN=1          -> log intended sends without sending

set -uo pipefail

# launchd/cron may not export HOME; derive it safely before using it.
: "${HOME:=$(cd ~ 2>/dev/null && pwd || echo /tmp)}"

INTERVAL="${INTERVAL:-15}"
DRY_RUN="${DRY_RUN:-0}"
TAIL_LINES="${TAIL_LINES:-30}"
PAUSE_FILE="${PAUSE_FILE:-$HOME/.claude/claude-watcher.pause}"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

# --- iTerm2: read via `contents of session`, send via `write text` -----------
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
        set tailTxt to ""
        repeat with i from startIdx to cnt
          set tailTxt to tailTxt & (item i of para) & linefeed
        end repeat
        set isClaude to (tailTxt contains "shift+tab to cycle") or (tailTxt contains "for shortcuts") or (tailTxt contains "⏵⏵") or (tailTxt contains "for agents") or (tailTxt contains "context used") or ((tailTxt contains "Context") and (tailTxt contains "Usage"))
        set hasBanner to (tailTxt contains "API Error:")
        set isTransient to (tailTxt contains "temporarily limiting requests") or (tailTxt contains "Overloaded") or (tailTxt contains "overloaded_error") or (tailTxt contains "Error: 529") or (tailTxt contains "server-side issue")
        set isBusy to (tailTxt contains "esc to interrupt")
        if isClaude and hasBanner and isTransient and (not isBusy) then
          if "$DRY_RUN" is "0" then
            tell s to write text "continue"
          end if
          set acted to acted & "iterm:" & (id of s) & linefeed
        end if
      end repeat
    end repeat
  end repeat
  return acted
end tell
OSA
}

# --- Apple Terminal: read via `contents of tab`, send via `do script ... in tab`
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
      set tailTxt to ""
      repeat with i from startIdx to cnt
        set tailTxt to tailTxt & (item i of para) & linefeed
      end repeat
      set isClaude to (tailTxt contains "shift+tab to cycle") or (tailTxt contains "for shortcuts") or (tailTxt contains "⏵⏵") or (tailTxt contains "for agents") or (tailTxt contains "context used") or ((tailTxt contains "Context") and (tailTxt contains "Usage"))
      set hasBanner to (tailTxt contains "API Error:")
      set isTransient to (tailTxt contains "temporarily limiting requests") or (tailTxt contains "Overloaded") or (tailTxt contains "overloaded_error") or (tailTxt contains "Error: 529") or (tailTxt contains "server-side issue")
      set isBusy to (tailTxt contains "esc to interrupt")
      if isClaude and hasBanner and isTransient and (not isBusy) then
        if "$DRY_RUN" is "0" then
          do script "continue" in tab ti of w
        end if
        set acted to acted & "terminal:" & wi & "." & ti & linefeed
      end if
    end repeat
  end repeat
  return acted
end tell
OSA
}

report() {
  local out="$1"
  [ -z "${out//[$'\n ']/}" ] && return 0
  while IFS= read -r tgt; do
    [ -z "$tgt" ] && continue
    if [ "$DRY_RUN" = "0" ]; then
      log "transient API error detected -> sent 'continue' to $tgt"
    else
      log "[DRY_RUN] would send 'continue' to $tgt"
    fi
  done <<< "$out"
}

reachability() {
  osascript <<'OSA' 2>/dev/null
set itc to "n/a"
set tm to "n/a"
try
  set itRun to (application "iTerm2" is running)
  if itRun then
    tell application "iTerm2"
      set c to 0
      repeat with w in windows
        repeat with t in tabs of w
          repeat with s in sessions of t
            set c to c + 1
          end repeat
        end repeat
      end repeat
      set itc to (c as string)
    end tell
  else
    set itc to "not running"
  end if
end try
try
  set tmRun to (application "Terminal" is running)
  if tmRun then
    tell application "Terminal"
      set c to 0
      repeat with wi from 1 to (count of windows)
        set c to c + (count of tabs of window wi)
      end repeat
      set tm to (c as string)
    end tell
  else
    set tm to "not running"
  end if
end try
return "iterm=" & itc & " terminal=" & tm
OSA
}

log "claude-continue-watcher started (iTerm2 + Terminal.app, interval=${INTERVAL}s, tail=${TAIL_LINES}, dry_run=${DRY_RUN}, pause_file=${PAUSE_FILE})"
log "reachability: $(reachability)  (terminal=0 while sessions exist => grant 'Terminal' Automation to the watcher)"
while true; do
  if [ -f "$PAUSE_FILE" ]; then sleep "$INTERVAL"; continue; fi
  report "$(scan_iterm)"
  report "$(scan_terminal)"
  sleep "$INTERVAL"
done
