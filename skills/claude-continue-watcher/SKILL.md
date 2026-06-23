---
name: claude-continue-watcher
description: 'Auto-recover Claude Code CLI sessions from transient API rate-limit / overload errors (API Error temporarily limiting requests, 529 Overloaded) by detecting the idle error banner and sending continue every few seconds until the API recovers. Use when asked to auto-continue, auto-retry, babysit, or unstick Claude Code sessions that keep hitting rate limits or 529s. Cross-platform via tmux (Linux, macOS, Windows WSL), plus native iTerm2 + Apple Terminal on macOS.'
---

# claude-continue-watcher

A tiny background watcher that types `continue` for you when Claude Code stalls
on a **transient** API error, so a long run resumes itself instead of sitting
idle until you notice.

## What it detects

It scans the **live tail** of each terminal session and acts only when ALL are true:

1. **It's a real Claude Code session** — the footer chrome (`shift+tab to cycle`
   / `? for shortcuts`) is present. This prevents firing into a plain shell, a
   pager, or a `tail -f` of the watcher's own log.
2. **It's idle** — `esc to interrupt` is absent (Claude is not mid-turn).
3. **There's an error banner** — the literal `API Error:` line.
4. **The error is transient/retry-able** — one of: `temporarily limiting
   requests`, `Overloaded`, `overloaded_error`, `529`, `server-side issue`.

Then it sends `continue` + Enter and re-checks every `INTERVAL` seconds (default
15). After a send the session becomes busy, so it won't over-send; it only
re-fires once the session is idle-errored again. Real usage-limit errors, auth
errors, and prose never trigger it.

## Platforms

The watcher needs to read a session's live screen and inject keystrokes. Two
backends provide that:

- **tmux** — the cross-platform path. Works on **Linux, macOS, and Windows
  (WSL)**. Run your Claude Code sessions inside tmux.
- **macOS native** — scans both **iTerm2** (`write text`) and **Apple Terminal**
  (`do script`), no tmux needed.

`install.sh` auto-picks tmux if a tmux server is running, otherwise the macOS
native backend. Force with `WATCHER=tmux` or `WATCHER=iterm`.

The macOS backend needs Automation permission to control iTerm2 and Terminal
(approve the one-time "control" prompts, or grant under System Settings >
Privacy & Security > Automation). Not supported: **native Windows** terminals
without WSL (no buffer-read API).

## Install

```bash
bash install.sh                # auto-detect backend + service manager
WATCHER=tmux bash install.sh   # force tmux (Linux / macOS / WSL)
```

Service manager: launchd on macOS, systemd --user on Linux (nohup fallback).
With the iTerm2 backend, the first run triggers a one-time macOS Automation
consent prompt ("bash wants to control iTerm") — approve it under
System Settings > Privacy & Security > Automation.

## Use / manage

- Logs: `~/.claude/logs/claude-continue-watcher.log`
- Pause (kill switch): `touch ~/.claude/claude-watcher.pause`
- Resume: `rm ~/.claude/claude-watcher.pause`
- macOS service: `launchctl {unload|load} ~/Library/LaunchAgents/sh.skills.claude-continue-watcher.plist`
- Linux service: `systemctl --user {status|stop|restart} claude-continue-watcher`
- Uninstall: `bash uninstall.sh`

## Tunables (env)

| Var | Default | Meaning |
|-----|---------|---------|
| `INTERVAL` | `15` | Seconds between scans |
| `TAIL_LINES` | `30` | How many trailing lines to inspect |
| `DRY_RUN` | `0` | `1` = log intended sends, send nothing |
| `SKIP_PATTERN` | _(empty)_ | tmux only: regex of session names to never touch |
| `PAUSE_FILE` | `~/.claude/claude-watcher.pause` | Touch to pause |

## Run manually (no service)

```bash
INTERVAL=15 bash watcher-iterm.sh   # macOS / iTerm2
INTERVAL=15 bash watcher-tmux.sh    # Linux / tmux
```

## Safety notes

- Only ever sends the single word `continue` + Enter, and only into a session
  that passes the 4 checks above.
- The `SKIP_PATTERN` (tmux) lets you exclude sensitive sessions (e.g. anything
  matching `prod|deploy`).
- It resumes autonomous agents automatically. If you want a session to pause on
  a rate limit for manual review, add it to `SKIP_PATTERN` or `touch` the pause
  file.
