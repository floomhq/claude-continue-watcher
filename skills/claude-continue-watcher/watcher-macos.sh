#!/usr/bin/env bash
# claude-continue-watcher.sh  (macOS / iTerm2 + Terminal.app)  — v2 detector
#
# Watches every iTerm2 and Apple Terminal session and types "continue" into a
# Claude Code session that has STALLED on a transient API error or hit its
# 5h/weekly usage cap. v2 uses POSITIONAL detection (see decide_pane): it acts
# only when the rendered error banner is the turn-result line right above an
# idle input prompt, and never while Claude is generating — so it resumes a
# session stuck behind a background shell, yet never fires on a session that is
# merely displaying the words (e.g. a chat about rate limits) or working.
#
# Cadences: transient errors every INTERVAL (15s); usage cap every
# USAGE_INTERVAL (600s = 10 min).  Kill switch: touch $PAUSE_FILE.  DRY_RUN=1
# logs intended sends.

set -uo pipefail
: "${HOME:=$(cd ~ 2>/dev/null && pwd || echo /tmp)}"

INTERVAL="${INTERVAL:-15}"
USAGE_INTERVAL="${USAGE_INTERVAL:-600}"
DRY_RUN="${DRY_RUN:-0}"
PAUSE_FILE="${PAUSE_FILE:-$HOME/.claude/claude-watcher.pause}"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

# --- decide_pane: stdin = pane text; stdout = "transient" | "usage" | "" ------
# (sed normalizes the non-breaking space U+00A0 that Claude renders after the
#  "❯" prompt, so the idle-prompt check matches.)
decide_pane() {
  sed $'s/\xc2\xa0/ /g' | awk '
  { L[NR]=$0 }
  END {
    n=NR; if (n==0) { print ""; exit }
    isclaude=0
    for (i=1;i<=n;i++) if (L[i] ~ /shift\+tab to cycle|⏵⏵|for agents|context used/ || (L[i] ~ /Context/ && L[i] ~ /Usage/)) isclaude=1
    if (!isclaude) { print ""; exit }
    for (i=1;i<=n;i++) { l=L[i]
      if (l ~ /ing… \(/ || l ~ /↓ [0-9.]+k? tokens/ || l ~ /⎿ +Running…/) { print ""; exit } }
    promptidx=0
    for (i=n;i>=1;i--) { t=L[i]; gsub(/^[ \t]+|[ \t]+$/,"",t)
      if (t=="❯" || t=="›" || t=="> " || t==">") { promptidx=i; break } }
    if (promptidx==0) { print ""; exit }
    c1=""; c0=""; got=0
    for (i=promptidx-1; i>=1; i--) { t=L[i]; gsub(/^[ \t]+|[ \t]+$/,"",t)
      if (t=="" || t ~ /^[-─—_]+$/ || t ~ /^✻/) continue
      if (got==0) { c1=t; got=1; continue }
      c0=t; break }
    if (got==0) { print ""; exit }
    h1=c1; sub(/^⏺[ \t]*/,"",h1); h0=c0; sub(/^⏺[ \t]*/,"",h0)
    tk="temporarily limiting requests|Overloaded|overloaded_error|Error: 529|server-side issue|Rate limited"
    if (h1 ~ /^API Error:/ && h1 ~ tk) { print "transient"; exit }
    if (length(h1) < 40 && h1 ~ /^(Rate limited|529 Overloaded|Overloaded|server-side issue)/ && h0 ~ /^API Error:/) { print "transient"; exit }
    if (h1 ~ /hit your/ && h1 ~ /limit/ && h1 ~ /resets/) { print "usage"; exit }
    print ""
  }'
}

# --- dump every session: marker line "%%CCW%% <app> <id>" then its contents --
dump_sessions() {
  osascript <<'OSA' 2>/dev/null
set out to ""
try
  if application "iTerm2" is running then
    tell application "iTerm2"
      repeat with w in windows
        repeat with t in tabs of w
          repeat with s in sessions of t
            set txt to ""
            try
              set txt to contents of s
            end try
            set out to out & "%%CCW%% iterm " & (id of s) & linefeed & txt & linefeed
          end repeat
        end repeat
      end repeat
    end tell
  end if
end try
try
  if application "Terminal" is running then
    tell application "Terminal"
      repeat with wi from 1 to (count of windows)
        repeat with ti from 1 to (count of tabs of window wi)
          set txt to ""
          try
            set txt to (contents of tab ti of window wi)
          end try
          set out to out & "%%CCW%% terminal " & wi & "." & ti & linefeed & txt & linefeed
        end repeat
      end repeat
    end tell
  end if
end try
return out
OSA
}

send_iterm()    { osascript -e "tell application \"iTerm2\" to repeat with w in windows" -e "repeat with t in tabs of w" -e "repeat with s in sessions of t" -e "if (id of s) is \"$1\" then tell s to write text \"continue\"" -e "end repeat" -e "end repeat" -e "end repeat" 2>/dev/null; }
send_terminal() { local wi="${1%%.*}" ti="${1##*.}"; osascript -e "tell application \"Terminal\" to do script \"continue\" in tab $ti of window $wi" 2>/dev/null; }

act() { # $1=cur_id ("iterm <id>" | "terminal <w.t>")  $2=reason
  local app="${1%% *}" tgt="${1#* }"
  if [ "$DRY_RUN" = "0" ]; then
    [ "$app" = "iterm" ] && send_iterm "$tgt"
    [ "$app" = "terminal" ] && send_terminal "$tgt"
    log "$2 detected -> sent 'continue' to $1"
  else
    log "[DRY_RUN] would send 'continue' to $1 ($2)"
  fi
}

maybe_act() { # $1=cur_id  $2=cur_buf
  local r; r="$(printf '%s' "$2" | decide_pane)"
  if [ "$r" = "transient" ] || { [ "$r" = "usage" ] && [ "$DO_USAGE" = "1" ]; }; then act "$1" "$r"; fi
}

last_usage=0; DO_USAGE=0
log "claude-continue-watcher started (v2, iTerm2 + Terminal.app, interval=${INTERVAL}s, usage_interval=${USAGE_INTERVAL}s, dry_run=${DRY_RUN})"
while true; do
  if [ -f "$PAUSE_FILE" ]; then sleep "$INTERVAL"; continue; fi
  now="$(date +%s)"; DO_USAGE=0
  if [ "$(( now - last_usage ))" -ge "$USAGE_INTERVAL" ]; then DO_USAGE=1; last_usage="$now"; fi
  cur_id=""; cur_buf=""
  while IFS= read -r line; do
    if [[ "$line" == "%%CCW%% "* ]]; then
      [ -n "$cur_id" ] && maybe_act "$cur_id" "$cur_buf"
      cur_id="${line#%%CCW%% }"; cur_buf=""
    else
      cur_buf+="$line"$'\n'
    fi
  done < <(dump_sessions)
  [ -n "$cur_id" ] && maybe_act "$cur_id" "$cur_buf"
  sleep "$INTERVAL"
done
