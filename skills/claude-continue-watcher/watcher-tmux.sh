#!/usr/bin/env bash
# claude-continue-watcher (tmux) — v2 detector
#
# Types "continue" into a Claude Code tmux pane that has STALLED on a transient
# API error or hit its 5h/weekly usage cap. v2 uses POSITIONAL detection (see
# decide_pane): acts only when the rendered error banner is the turn-result
# line right above an idle input prompt, and never while Claude is generating —
# so it resumes a session stuck behind a background shell, yet never fires on a
# session merely displaying the words (a chat about rate limits) or working.
#
# Cadences: transient every INTERVAL (15s); usage cap every USAGE_INTERVAL
# (600s).  touch $PAUSE_FILE to pause.  SKIP_PATTERN='regex' to exclude
# sessions by name.  DRY_RUN=1 logs intended sends.

set -uo pipefail
: "${HOME:=$(cd ~ 2>/dev/null && pwd || echo /root)}"

INTERVAL="${INTERVAL:-15}"
USAGE_INTERVAL="${USAGE_INTERVAL:-600}"
DRY_RUN="${DRY_RUN:-0}"
TAIL_LINES="${TAIL_LINES:-40}"
PAUSE_FILE="${PAUSE_FILE:-$HOME/.claude/claude-watcher.pause}"
SKIP_PATTERN="${SKIP_PATTERN:-}"

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
command -v tmux >/dev/null 2>&1 || { echo "tmux not found"; exit 1; }

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

last_usage=0; DO_USAGE=0
log "claude-continue-watcher started (v2, tmux, interval=${INTERVAL}s, usage_interval=${USAGE_INTERVAL}s, dry_run=${DRY_RUN}, pause_file=${PAUSE_FILE})"
while true; do
  if [ -f "$PAUSE_FILE" ]; then sleep "$INTERVAL"; continue; fi
  now="$(date +%s)"; DO_USAGE=0
  if [ "$(( now - last_usage ))" -ge "$USAGE_INTERVAL" ]; then DO_USAGE=1; last_usage="$now"; fi
  if tmux has-session 2>/dev/null; then
    while IFS= read -r pane; do
      [ -z "$pane" ] && continue
      sess="${pane%%:*}"
      if [ -n "$SKIP_PATTERN" ] && printf '%s' "$sess" | grep -qE "$SKIP_PATTERN"; then continue; fi
      r="$(tmux capture-pane -p -t "$pane" 2>/dev/null | tail -n "$TAIL_LINES" | decide_pane)" || continue
      if [ "$r" = "transient" ] || { [ "$r" = "usage" ] && [ "$DO_USAGE" = "1" ]; }; then
        if [ "$DRY_RUN" = "0" ]; then
          tmux send-keys -t "$pane" "continue" Enter
          log "$r detected -> sent 'continue' to pane $pane"
        else
          log "[DRY_RUN] would send 'continue' to pane $pane ($r)"
        fi
      fi
    done < <(tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}')
  fi
  sleep "$INTERVAL"
done
