"""Static game + shared score API. Scores are client-reported, not authoritative combat results."""
from __future__ import annotations
import collections
from contextlib import contextmanager
import json
import os
from pathlib import Path
import sqlite3
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, quote, unquote, urlsplit
import mimetypes

VERSION = "office-expansion-v3"
RULESET = "balance-2026-11-07-v2"
MAX_BODY = 64 * 1024
FIELDS = ("name", "score", "wave", "boss", "level", "kills", "time", "mode", "version", "ruleset", "hero")
HEROES = {"male", "female", "intern", "programmer", "fufu"}


class ApiError(Exception):
    def __init__(self, code, status=400):
        self.code, self.status = code, status


def validate(payload):
    if not isinstance(payload, dict):
        raise ApiError("invalid_payload")
    name = payload.get("name")
    if not isinstance(name, str) or not name.strip() or any(ord(c) < 32 or ord(c) == 127 for c in name):
        raise ApiError("invalid_name")
    try:
        name.encode("utf-8")
    except UnicodeError:
        raise ApiError("invalid_name") from None
    run_id = payload.get("run_id")
    try:
        run_id = str(uuid.UUID(run_id))
    except (ValueError, AttributeError, TypeError):
        raise ApiError("invalid_run_id") from None
    if payload.get("version") != VERSION or payload.get("ruleset") != RULESET:
        raise ApiError("stale_ruleset", 409)
    if payload.get("balanceVersion", RULESET) != RULESET:
        raise ApiError("stale_ruleset", 409)
    mode = payload.get("mode")
    if mode not in ("campaign", "endless") or payload.get("hero") not in HEROES:
        raise ApiError("invalid_mode_or_hero")
    entry = {"run_id": run_id, **{k: payload.get(k) for k in FIELDS}}
    entry["name"] = name.strip()
    limits = {"score": (0, 2147483647), "wave": (0, 10000), "boss": (0, 10000), "level": (1, 1000), "kills": (0, 10000000), "time": (0, 86400)}
    for key, (low, high) in limits.items():
        value = entry[key]
        if type(value) is not int or not low <= value <= high:
            raise ApiError("invalid_" + key)
    expected = 1000 * entry["wave"] + 1500 * entry["boss"] + 12 * entry["kills"] + 40 * entry["level"] + 3 * min(3600, entry["time"])
    max_boss = entry["wave"] // 3 if mode == "endless" else 3
    if entry["boss"] > max_boss or not expected <= entry["score"] <= expected + 2:
        raise ApiError("score_mismatch")
    # Legacy client formulas can include fractional seconds (+0..2 points).
    # Store the whole-second recomputation for consistent ranking.
    entry["score"] = expected
    return entry


def wire(entries):
    """Percent-encoded names avoid Lua JSON parsing and delimiter ambiguity."""
    return "".join("|".join([quote(e["name"], safe=""), *[str(e[k]) for k in ("score", "wave", "boss", "level", "kills", "time", "ts")]]) + ";" for e in entries)


class ScoreStore:
    def __init__(self, path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.connect() as con:
            con.execute("PRAGMA journal_mode=WAL")
            con.execute("""CREATE TABLE IF NOT EXISTS runs (
                id INTEGER PRIMARY KEY, run_id TEXT NOT NULL UNIQUE,
                name TEXT NOT NULL, score INTEGER NOT NULL, wave INTEGER NOT NULL,
                boss INTEGER NOT NULL, level INTEGER NOT NULL, kills INTEGER NOT NULL,
                time INTEGER NOT NULL, mode TEXT NOT NULL, version TEXT NOT NULL,
                ruleset TEXT NOT NULL, hero TEXT NOT NULL, ts INTEGER NOT NULL)""")
            con.execute("CREATE INDEX IF NOT EXISTS ranked_runs ON runs(mode, version, ruleset, score DESC, wave DESC, time ASC, ts ASC, id ASC)")

    @contextmanager
    def connect(self):
        con = sqlite3.connect(self.path, timeout=10)
        con.row_factory = sqlite3.Row
        try:
            with con:
                yield con
        finally:
            con.close()

    def top(self, mode, limit=20):
        with self.connect() as con:
            rows = con.execute("SELECT * FROM runs WHERE mode=? AND version=? AND ruleset=? ORDER BY score DESC,wave DESC,time ASC,ts ASC,id ASC LIMIT ?", (mode, VERSION, RULESET, limit)).fetchall()
        return [dict(row) for row in rows]

    def submit(self, entry):
        with self.connect() as con:
            con.execute("BEGIN IMMEDIATE")
            old = con.execute("SELECT * FROM runs WHERE run_id=?", (entry["run_id"],)).fetchone()
            if old:
                if any(old[k] != entry[k] for k in FIELDS):
                    raise ApiError("run_id_conflict", 409)
                record = dict(old)
            else:
                keys = ("run_id", *FIELDS, "ts")
                data = {**entry, "ts": int(time.time())}
                cursor = con.execute("INSERT INTO runs (" + ",".join(keys) + ") VALUES (" + ",".join("?" for _ in keys) + ")", tuple(data[k] for k in keys))
                record = {**data, "id": cursor.lastrowid}
            rank = con.execute("SELECT rank FROM (SELECT run_id,ROW_NUMBER() OVER (ORDER BY score DESC,wave DESC,time ASC,ts ASC,id ASC) rank FROM runs WHERE mode=? AND version=? AND ruleset=?) WHERE run_id=?", (entry["mode"], VERSION, RULESET, entry["run_id"])).fetchone()[0]
        return rank, bool(old), record


class RateLimit:
    def __init__(self):
        self.lock, self.buckets = threading.Lock(), collections.OrderedDict()

    def allow(self, key, maximum):
        now = time.monotonic()
        with self.lock:
            while self.buckets and next(iter(self.buckets.values()))[-1] < now - 60:
                self.buckets.popitem(last=False)
            bucket = [t for t in self.buckets.pop(key, []) if t >= now - 60]
            allowed = len(bucket) < maximum
            if allowed:
                bucket.append(now)
            self.buckets[key] = bucket
            if len(self.buckets) > 4096:
                self.buckets.popitem(last=False)
            return allowed


def make_server(host, port, web_root, data_dir):
    root = Path(web_root).resolve()
    store, limiter = ScoreStore(Path(data_dir) / "scores.sqlite3"), RateLimit()

    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.0"

        def log_message(self, fmt, *args):
            # Do not log user nicknames or request bodies.
            print("[http] " + fmt % args, flush=True)

        def send_json(self, payload, status=200):
            data = json.dumps(payload, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            u = urlsplit(self.path)
            if u.path == "/api/config":
                return self.send_json({"ok": True, "version": VERSION, "ruleset": RULESET, "balanceVersion": RULESET, "source": "client-reported", "authoritativeCombat": False})
            if u.path == "/api/health":
                return self.send_json({"ok": True, "storage": "sqlite", "version": VERSION, "ruleset": RULESET})
            if u.path == "/api/leaderboard":
                if not limiter.allow((self.client_address[0], "get"), 180):
                    return self.send_json({"ok": False, "error": "rate_limited"}, 429)
                q = parse_qs(u.query)
                mode = q.get("mode", ["endless"])[0]
                if mode not in ("endless", "campaign"):
                    return self.send_json({"ok": False, "error": "invalid_mode"}, 400)
                if q.get("version", [VERSION])[0] != VERSION or q.get("ruleset", [RULESET])[0] != RULESET:
                    return self.send_json({"ok": False, "error": "stale_ruleset"}, 409)
                try:
                    entries = store.top(mode)
                except sqlite3.Error:
                    return self.send_json({"ok": False, "error": "storage_unavailable"}, 503)
                return self.send_json({"ok": True, "entries": entries, "wire": wire(entries), "mode": mode, "version": VERSION, "ruleset": RULESET, "source": "client-reported"})
            if u.path.startswith("/api/"):
                return self.send_json({"ok": False, "error": "not_found"}, 404)
            # Serve only game build artifacts, never Python, Dockerfiles, or DBs.
            relative = unquote(u.path).lstrip("/") or "index.html"
            file = (root / relative).resolve()
            if not file.is_relative_to(root) or relative.split("/")[0] not in ("index.html", "assets", "js", "css", "vendor") or any(p.startswith(".") for p in Path(relative).parts) or not file.is_file():
                return self.send_json({"ok": False, "error": "not_found"}, 404)
            data = file.read_bytes()
            if relative == "index.html":
                marker = b'<script>window.OFFWORK_API_ENABLED=true;</script>'
                data = data.replace(b"<head>", b"<head>" + marker, 1)
            self.send_response(200)
            self.send_header("Content-Type", mimetypes.guess_type(file.name)[0] or "application/octet-stream")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-cache")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.end_headers()
            self.wfile.write(data)

        def do_POST(self):
            if urlsplit(self.path).path != "/api/leaderboard":
                return self.send_json({"ok": False, "error": "not_found"}, 404)
            if not limiter.allow((self.client_address[0], "post"), 60):
                return self.send_json({"ok": False, "error": "rate_limited"}, 429)
            try:
                length = int(self.headers.get("Content-Length", "-1"))
                if length < 0:
                    raise ApiError("length_required", 411)
                if length > MAX_BODY:
                    raise ApiError("body_too_large", 413)
                if self.headers.get("Content-Type", "").split(";", 1)[0].strip().lower() != "application/json":
                    raise ApiError("unsupported_media_type", 415)
                self.connection.settimeout(5)
                raw = self.rfile.read(length)
                if len(raw) != length:
                    raise ApiError("invalid_payload")
                payload = json.loads(raw, parse_constant=lambda _: (_ for _ in ()).throw(ValueError("nonfinite")))
                entry = validate(payload)
                rank, repeated, record = store.submit(entry)
                entries = store.top(entry["mode"])
                return self.send_json({"ok": True, "rank": rank, "repeated": repeated, "run_id": record["run_id"], "entries": entries, "wire": wire(entries), "source": "client-reported"})
            except ApiError as err:
                return self.send_json({"ok": False, "error": err.code}, err.status)
            except (ValueError, UnicodeError, TimeoutError):
                return self.send_json({"ok": False, "error": "invalid_payload"}, 400)
            except sqlite3.Error:
                return self.send_json({"ok": False, "error": "storage_unavailable"}, 503)

    server = ThreadingHTTPServer((host, port), Handler)
    server.daemon_threads = True
    return server


if __name__ == "__main__":
    root = Path(os.environ.get("WEB_ROOT", Path(__file__).parent))
    server = make_server("0.0.0.0", int(os.environ.get("PORT", "7860")), root, os.environ.get("SCORE_DATA_DIR", "/mnt/workspace"))
    print("[scores] HTTP ready on 0.0.0.0:%s; version=%s ruleset=%s; client-reported, not authoritative combat" % (server.server_port, VERSION, RULESET), flush=True)
    server.serve_forever()
