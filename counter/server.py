#!/usr/bin/env python3
"""ccw-counter: global tally of auto-continues sent by claude-continue-watcher.
Endpoints (CORS open):
  GET  /count          -> {"total": N}
  POST /ping {"id","n"} -> increment by n (1..20), per-id+ip rate limited; {"total": N}
Only a count + anonymous random id are ever stored. No hostnames, no content.
"""
import json, sqlite3, time, os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DB = "/opt/ccw-counter/counter.db"
SEED = int(os.environ.get("CCW_SEED", "0"))

def db():
    c = sqlite3.connect(DB, timeout=5)
    c.execute("CREATE TABLE IF NOT EXISTS counter(id INTEGER PRIMARY KEY CHECK(id=1), total INTEGER)")
    c.execute("CREATE TABLE IF NOT EXISTS hits(key TEXT PRIMARY KEY, ts REAL)")
    c.execute("INSERT OR IGNORE INTO counter(id,total) VALUES(1,?)", (SEED,))
    return c

def get_total():
    c = db()
    try: return c.execute("SELECT total FROM counter WHERE id=1").fetchone()[0]
    finally: c.close()

def add(n, rl_key):
    c = db()
    try:
        now = time.time()
        row = c.execute("SELECT ts FROM hits WHERE key=?", (rl_key,)).fetchone()
        if row and now - row[0] < 3:   # min 3s between pings per id+ip
            return c.execute("SELECT total FROM counter WHERE id=1").fetchone()[0]
        c.execute("INSERT OR REPLACE INTO hits(key,ts) VALUES(?,?)", (rl_key, now))
        c.execute("UPDATE counter SET total=total+? WHERE id=1", (n,))
        c.commit()
        return c.execute("SELECT total FROM counter WHERE id=1").fetchone()[0]
    finally: c.close()

class H(BaseHTTPRequestHandler):
    def _send(self, code, obj):
        b = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers(); self.wfile.write(b)
    def do_OPTIONS(self): self._send(204, {})
    def do_GET(self):
        if self.path.rstrip("/") in ("/count", "/ccw/count"): self._send(200, {"total": get_total()})
        elif self.path.rstrip("/") in ("", "/ccw", "/health"): self._send(200, {"ok": True})
        else: self._send(404, {"error": "not found"})
    def do_POST(self):
        if self.path.rstrip("/") not in ("/ping", "/ccw/ping"): return self._send(404, {"error":"not found"})
        try:
            ln = int(self.headers.get("Content-Length", 0))
            data = json.loads(self.rfile.read(ln) or "{}")
        except Exception: data = {}
        n = data.get("n", 1)
        if not isinstance(n, int) or n < 1 or n > 20: n = 1
        iid = str(data.get("id", ""))[:64] or "anon"
        ip = self.headers.get("X-Forwarded-For", self.client_address[0]).split(",")[0].strip()
        self._send(200, {"total": add(n, iid + "|" + ip)})
    def log_message(self, *a): pass

if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 8799), H).serve_forever()
