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
