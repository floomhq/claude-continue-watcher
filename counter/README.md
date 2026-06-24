# ccw-counter

The tiny backend behind the live counter at https://claude-continue-watcher.vercel.app

- `GET  /count` → `{"total": N}` — the global tally.
- `POST /ping` `{"id","n"}` → increments by `n` (1–20), rate-limited per id+ip.

It stores **only** a running integer and, transiently, a random anonymous
install id for rate-limiting. No hostnames, no usernames, no terminal content,
ever. Runs as a single stdlib-Python service behind nginx (see `server.py`).

## Telemetry is opt-in
The watcher never phones home unless you set `CCW_TELEMETRY=1`. When on, it
sends a `+N` count and a random id generated once at `~/.claude/ccw-id`.
Override the endpoint with `CCW_ENDPOINT`, or just leave telemetry off.
