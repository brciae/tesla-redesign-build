import json
import tempfile
import unittest
import threading
import urllib.request
import urllib.error
from http.server import HTTPServer
from pathlib import Path
from store import Archive, handler_for

VIN = "LRWYGCEK0NC000001"
OTHER = "LRWYGCEK0NC000002"


def payload(vin=VIN, value=40):
    return json.dumps({"vin": vin, "createdAt": "2026-01-01T10:00:00Z",
                       "data": [{"key": "Soc", "value": {"doubleValue": value}}]}).encode()


class ArchiveTests(unittest.TestCase):
    def test_encrypted_vault_persists_with_compare_and_swap_without_touching_records(self):
        import base64
        sealed = base64.b64encode(b"opaque-encrypted-fixture" * 3).decode()
        self.archive.ingest("tesla_V", 0, 1, VIN.encode(), payload())
        self.assertEqual(self.archive.vault(), {"revision": 0, "sealed": ""})
        self.assertEqual(self.archive.save_vault(0, sealed), {"revision": 1})
        self.assertIsNone(self.archive.save_vault(0, sealed))
        reopened = Archive(self.path)
        self.assertEqual(reopened.vault(), {"revision": 1, "sealed": sealed})
        self.assertEqual(len(reopened.page(VIN, 0)["payloads"]), 1)
        for value in ("bad base64!", "", base64.b64encode(b"x" * 262145).decode()):
            with self.assertRaises(ValueError):
                reopened.save_vault(1, value)
        self.assertEqual(reopened.vault()["revision"], 1)

    def test_vault_http_authentication_and_conflict(self):
        import base64
        token = "fixture-archive-token-that-is-not-a-real-secret"
        server = HTTPServer(("127.0.0.1", 0), handler_for(self.archive, token, {"ready": True}))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        url = "http://127.0.0.1:" + str(server.server_port) + "/v1/app-vault"
        body = json.dumps({"revision": 0, "sealed": base64.b64encode(b"fixture" * 8).decode()}).encode()
        try:
            for method, data in (("GET", None), ("PUT", body)):
                with self.assertRaises(urllib.error.HTTPError) as denied:
                    urllib.request.urlopen(urllib.request.Request(url, data=data, method=method))
                self.assertEqual(denied.exception.code, 401)
                denied.exception.close()
            headers = {"Authorization": "Bearer " + token, "Content-Type": "application/json"}
            with urllib.request.urlopen(urllib.request.Request(url, headers=headers)) as response:
                self.assertEqual(json.load(response)["revision"], 0)
            with urllib.request.urlopen(urllib.request.Request(url, data=body, headers=headers, method="PUT")) as response:
                self.assertEqual(json.load(response)["revision"], 1)
            with self.assertRaises(urllib.error.HTTPError) as conflict:
                urllib.request.urlopen(urllib.request.Request(url, data=body, headers=headers, method="PUT"))
            self.assertEqual(conflict.exception.code, 409)
            conflict.exception.close()
        finally:
            server.shutdown(); server.server_close(); thread.join()

    def test_incremental_cursor_includes_late_packets_without_full_rescan(self):
        for i in range(81):
            self.archive.ingest("tesla_V", 0, i, VIN.encode(), payload(value=i))
        cursor, seen = 0, 0
        while True:
            page = self.archive.page(VIN, cursor)
            cursor = page["next"]
            seen += len(page["payloads"])
            if not page["more"]:
                break
        self.assertEqual(seen, 81)
        self.assertEqual(self.archive.page(VIN, cursor)["payloads"], [])
        late = json.loads(payload(value=82))
        late["createdAt"] = "2025-12-31T10:00:00Z"
        self.archive.ingest("tesla_V", 0, 81, VIN.encode(), json.dumps(late).encode())
        delta = self.archive.page(VIN, cursor)
        self.assertEqual(delta["payloads"], [late])
        self.assertEqual(self.archive.page(VIN, delta["next"])["payloads"], [])
    def test_receiver_ack_types_match_tesla_protocol(self):
        config = json.loads((Path(__file__).parent / "telemetry-config.example.json").read_text())
        self.assertIn("connectivity", config["records"])
        self.assertNotIn("connectivity", config["reliable_ack_sources"])
        self.assertEqual(set(config["reliable_ack_sources"]), {"V", "alerts", "errors"})

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "test.sqlite3"
        self.archive = Archive(self.path)

    def tearDown(self):
        self.temp.cleanup()

    def test_crash_replay_is_deduplicated_and_survives_reopen(self):
        for offset in (4, 4, 5):
            self.archive.ingest("tesla_V", 0, offset, VIN.encode(), payload())
        reopened = Archive(self.path)
        self.assertEqual(len(reopened.page(VIN, 0)["payloads"]), 1)
        with reopened.connect() as db:
            self.assertEqual(db.execute("SELECT offset FROM offsets").fetchone()[0], 5)

    def test_vehicle_isolation_and_original_timestamp(self):
        self.archive.ingest("tesla_V", 0, 0, VIN.encode(), payload())
        self.archive.ingest("tesla_V", 0, 1, OTHER.encode(), payload(OTHER))
        result = self.archive.page(VIN, 0)
        self.assertEqual(len(result["payloads"]), 1)
        self.assertEqual(result["payloads"][0]["createdAt"], "2026-01-01T10:00:00Z")

    def test_invalid_and_mismatched_records_preserved_but_not_measurements(self):
        for i, raw in enumerate((b"not-json", payload(OTHER), b'{"vin":"' + VIN.encode() + b'"}')):
            self.archive.ingest("tesla_V", 0, i, VIN.encode(), raw)
        self.assertEqual(self.archive.page(VIN, 0)["payloads"], [])
        with self.archive.connect() as db:
            self.assertEqual(db.execute("SELECT count(*) FROM events").fetchone()[0], 3)

    def test_pagination_no_gaps(self):
        for i in range(105):
            self.archive.ingest("tesla_V", 0, i, VIN.encode(), payload(value=i))
        first = self.archive.page(VIN, 0)
        second = self.archive.page(VIN, first["next"])
        third = self.archive.page(VIN, second["next"])
        self.assertTrue(first["more"])
        self.assertTrue(second["more"])
        self.assertFalse(third["more"])
        self.assertEqual(sum(len(p["payloads"]) for p in (first, second, third)), 105)

    def test_status_distinguishes_empty_archive_and_vehicle_delivery(self):
        self.assertEqual(self.archive.status(VIN)["measurement_packets"], 0)
        self.assertIsNone(self.archive.status(VIN)["last_vehicle_received_at"])
        self.archive.ingest("tesla_V", 0, 0, VIN.encode(), payload())
        self.archive.ingest("tesla_V", 0, 1, VIN.encode(), b"not-json")
        self.assertEqual(self.archive.status(VIN)["measurement_packets"], 1)
        self.assertIsNotNone(self.archive.status(VIN)["last_vehicle_received_at"])
        self.assertEqual(self.archive.status(OTHER)["measurement_packets"], 0)

    def test_api_requires_token_and_rejects_bad_cursor(self):
        token = "fixture-archive-token-that-is-not-a-real-secret"
        server = HTTPServer(("127.0.0.1", 0), handler_for(self.archive, token, {"ready": True}))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        base = "http://127.0.0.1:" + str(server.server_port)
        try:
            with self.assertRaises(urllib.error.HTTPError) as denied:
                urllib.request.urlopen(base + "/v1/telemetry?vin=" + VIN)
            self.assertEqual(denied.exception.code, 401)
            denied.exception.close()
            with self.assertRaises(urllib.error.HTTPError) as denied_status:
                urllib.request.urlopen(base + "/v1/status?vin=" + VIN)
            self.assertEqual(denied_status.exception.code, 401)
            denied_status.exception.close()
            request = urllib.request.Request(base + "/v1/status?vin=" + VIN,
                                             headers={"Authorization": "Bearer " + token})
            with urllib.request.urlopen(request) as response:
                status = json.load(response)
                self.assertTrue(status["archive_ready"])
                self.assertEqual(status["measurement_packets"], 0)
            request = urllib.request.Request(base + "/v1/telemetry?vin=" + VIN + "&after=-1",
                                             headers={"Authorization": "Bearer " + token})
            with self.assertRaises(urllib.error.HTTPError) as invalid:
                urllib.request.urlopen(request)
            self.assertEqual(invalid.exception.code, 400)
            invalid.exception.close()
            request = urllib.request.Request(base + "/v1/telemetry?vin=" + VIN,
                                             headers={"Authorization": "Bearer " + token})
            with urllib.request.urlopen(request) as response:
                self.assertEqual(json.load(response)["payloads"], [])
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


if __name__ == "__main__":
    unittest.main()
