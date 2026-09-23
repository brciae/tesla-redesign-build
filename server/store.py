"""Local Fleet archive. Commit SQLite before Kafka offsets; never log payloads."""
import hashlib
import hmac
import json
import os
import re
import sqlite3
import threading
import time
from contextlib import contextmanager
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

VIN = re.compile(r"^[A-HJ-NPR-Z0-9]{17}$")
TOPICS = ("tesla_V", "tesla_connectivity", "tesla_alerts", "tesla_errors")


class Archive:
    def __init__(self, path):
        self.path = str(path)
        with self.connect() as db:
            db.executescript("""
                PRAGMA journal_mode=WAL;
                CREATE TABLE IF NOT EXISTS events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    digest TEXT UNIQUE NOT NULL, vin TEXT NOT NULL,
                    kind TEXT NOT NULL, received REAL NOT NULL,
                    payload TEXT NOT NULL, valid INTEGER NOT NULL);
                CREATE INDEX IF NOT EXISTS event_vehicle ON events(vin,kind,id);
                CREATE TABLE IF NOT EXISTS offsets (
                    topic TEXT NOT NULL, partition INTEGER NOT NULL,
                    offset INTEGER NOT NULL, PRIMARY KEY(topic,partition));
            """)

    @contextmanager
    def connect(self):
        db = sqlite3.connect(self.path, timeout=15)
        db.execute("PRAGMA synchronous=FULL")
        try:
            with db:
                yield db
        finally:
            db.close()

    def ingest(self, topic, partition, offset, key, raw):
        if topic not in TOPICS or len(raw) > 4_000_000:
            raise ValueError("unsupported record size or topic")
        vin = key.decode("ascii")
        if not VIN.fullmatch(vin):
            raise ValueError("invalid vehicle key")
        # Preserve even an invalid JSON record in the archive for later recovery.
        # Invalid records never enter the app's measurement stream.
        text = raw.decode("utf-8", errors="replace")
        valid = False
        try:
            obj = json.loads(text)
            valid = isinstance(obj, dict) and obj.get("vin") == vin
            if topic == "tesla_V":
                stamp = obj.get("createdAt", obj.get("created_at"))
                if isinstance(stamp, str):
                    at = datetime.fromisoformat(stamp.replace("Z", "+00:00")).timestamp()
                else:
                    at = float(stamp["seconds"])
                valid = valid and 0 < at <= time.time() + 5 and isinstance(obj.get("data"), list)
                valid = valid and 0 < len(obj["data"]) <= 1000
            canonical = json.dumps(obj, sort_keys=True, separators=(",", ":"), allow_nan=False)
        except (ValueError, TypeError, KeyError, AttributeError):
            canonical = text
            valid = False
        digest = hashlib.sha256((topic + "\0" + vin + "\0" + canonical).encode()).hexdigest()
        # Both raw event and local offset are durable in the same transaction.
        with self.connect() as db:
            db.execute("INSERT OR IGNORE INTO events(digest,vin,kind,received,payload,valid) VALUES(?,?,?,?,?,?)",
                       (digest, vin, topic, time.time(), canonical, int(valid)))
            db.execute("INSERT INTO offsets VALUES(?,?,?) ON CONFLICT(topic,partition) DO UPDATE SET offset=max(offset,excluded.offset)",
                       (topic, partition, offset))

    def page(self, vin, after, limit=40):
        if not VIN.fullmatch(vin) or after < 0 or not 1 <= limit <= 40:
            raise ValueError("invalid request")
        with self.connect() as db:
            rows = db.execute("SELECT id,payload FROM events WHERE vin=? AND kind='tesla_V' AND valid=1 AND id>? ORDER BY id LIMIT ?",
                              (vin, after, limit + 1)).fetchall()
        selected, size = [], 0
        for row in rows[:limit]:
            # Stay below the iOS import's 5 MB total limit.
            if selected and size + len(row[1].encode()) > 4_500_000:
                break
            selected.append(row)
            size += len(row[1].encode())
        return {"payloads": [json.loads(row[1]) for row in selected],
                "next": selected[-1][0] if selected else after,
                "more": len(rows) > len(selected)}


def handler_for(archive, token, health):
    class Handler(BaseHTTPRequestHandler):
        def setup(self):
            super().setup()
            self.connection.settimeout(10)

        def log_message(self, *args):
            pass  # URL includes VIN; never put identifiers or tokens in access logs.

        def reply(self, code, obj):
            raw = json.dumps(obj, separators=(",", ":"), allow_nan=False).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(raw)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.end_headers()
            self.wfile.write(raw)

        def do_GET(self):
            route = urlsplit(self.path)
            if route.path == "/health":
                return self.reply(200 if health["ready"] else 503,
                                  {"ready": health["ready"], "service": "yl-fleet-archive"})
            auth = self.headers.get("Authorization", "")
            if not hmac.compare_digest(auth.encode(), ("Bearer " + token).encode()):
                return self.reply(401, {"error": "authentication_required"})
            if route.path != "/v1/telemetry":
                return self.reply(404, {"error": "not_found"})
            try:
                args = parse_qs(route.query, max_num_fields=4)
                page = archive.page(args.get("vin", [""])[0], int(args.get("after", ["0"])[0]))
                return self.reply(200, page)
            except (ValueError, TypeError):
                return self.reply(400, {"error": "invalid_request"})
            except sqlite3.Error:
                return self.reply(503, {"error": "storage_unavailable"})
    return Handler


def consume(archive, health):
    from confluent_kafka import Consumer, KafkaException
    consumer = Consumer({"bootstrap.servers": os.getenv("KAFKA_BOOTSTRAP", "kafka:9092"),
                         "group.id": "yl-sqlite-archive-v1", "auto.offset.reset": "earliest",
                         "enable.auto.commit": False, "enable.auto.offset.store": False,
                         "queued.max.messages.kbytes": 8192})
    consumer.subscribe(list(TOPICS))
    try:
        while True:
            msg = consumer.poll(1)
            if msg is None:
                # Metadata health checks are bounded; idle/sleeping cars are normal.
                consumer.list_topics(timeout=5)
                health["ready"] = True
                continue
            if msg.error():
                raise KafkaException(msg.error())
            archive.ingest(msg.topic(), msg.partition(), msg.offset(), msg.key() or b"", msg.value() or b"")
            consumer.commit(message=msg, asynchronous=False)
            health["ready"] = True
    finally:
        health["ready"] = False
        consumer.close()


def main():
    root = Path(os.getenv("ARCHIVE_PATH", "/data"))
    root.mkdir(parents=True, exist_ok=True)
    token = Path(os.getenv("API_TOKEN_FILE", "/run/secrets/api-token")).read_text().strip()
    if len(token) < 32:
        raise ValueError("a private API token of at least 32 characters is required")
    archive = Archive(root / "fleet.sqlite3")
    health = {"ready": False}
    def worker():
        while True:
            try:
                consume(archive, health)
            except Exception as error:
                health["ready"] = False
                # No exception body: broker errors can contain vehicle data.
                print("archive consumer retry:", type(error).__name__, flush=True)
                time.sleep(10)
    threading.Thread(target=worker, daemon=True).start()
    HTTPServer(("0.0.0.0", 8787), handler_for(archive, token, health)).serve_forever()


if __name__ == "__main__":
    main()
