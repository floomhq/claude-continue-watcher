# claude-continue-watcher

Claude Code rate limits are annoying. Less annoying if something types
`continue` for you every few seconds until the servers are back. :=)

This is a tiny background watcher that detects the **idle transient-error
banner** in a Claude Code session, `API Error: Server is temporarily limiting
requests`, `529 Overloaded`, etc., and sends `continue` until the API recovers.

Cross-platform via **tmux** (Linux, macOS, Windows/WSL), plus a native
**iTerm2** backend on macOS when you are not using tmux.

## Install

Via [skills.sh](https://skills.sh):

```bash
npx skills add floomhq/claude-continue-watcher
```

Then run the installer (auto-picks tmux if a tmux server is running, else iTerm2
on macOS; sets up launchd on macOS / systemd-user on Linux):

```bash
bash ~/.claude/skills/claude-continue-watcher/install.sh
# force a backend: WATCHER=tmux bash ~/.claude/skills/claude-continue-watcher/install.sh
```

Or clone and install directly:

```bash
git clone https://github.com/floomhq/claude-continue-watcher
bash claude-continue-watcher/skills/claude-continue-watcher/install.sh
```

## How it decides to act

It scans the live tail of each session and sends `continue` only when ALL hold:

1. **Real Claude session** — footer chrome (`shift+tab to cycle`) present, so it
   never fires into a bare shell or a `tail -f` of its own log.
2. **Idle** — `esc to interrupt` absent (not mid-turn).
3. **Error banner** — the literal `API Error:` line.
4. **Transient** — `temporarily limiting requests` / `Overloaded` /
   `overloaded_error` / `529` / `server-side issue`.

After a send the session goes busy, so it won't over-send; it re-fires only once
the session is idle-errored again. Real usage-limit and auth errors never trigger
it.

## Manage

```bash
touch ~/.claude/claude-watcher.pause   # pause (kill switch)
rm    ~/.claude/claude-watcher.pause   # resume
tail -f ~/.claude/logs/claude-continue-watcher.log
bash ~/.claude/skills/claude-continue-watcher/uninstall.sh
```

Tunables (`INTERVAL`, `TAIL_LINES`, `DRY_RUN`, `SKIP_PATTERN`) are documented in
[`skills/claude-continue-watcher/SKILL.md`](skills/claude-continue-watcher/SKILL.md).

## Platforms

| Backend | Where | Notes |
|---------|-------|-------|
| **tmux** | Linux, macOS, Windows (WSL) | Run your Claude Code sessions inside tmux. The cross-platform path. |
| **macOS native** | macOS | Scans both **iTerm2** and **Apple Terminal**, no tmux needed. First run needs a one-time Automation permission grant for each app. |

Not supported: **native Windows** terminals without WSL (no buffer-read API).
Force a backend with `WATCHER=tmux` or `WATCHER=iterm`.

## License

MIT
