import json
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request
from datetime import datetime, timezone
from http.server import HTTPServer
from pathlib import Path
from dashboard import snapshot
from store import Archive, handler_for

VIN = "LRWYGCEK0NC000001"
OTHER = "LRWYGCEK0NC000002"


class DashboardTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.archive = Archive(Path(self.directory.name) / "archive.sqlite3")

    def tearDown(self):
        self.directory.cleanup()

    def ingest(self, offset, at, fields):
        raw = json.dumps({"vin": VIN, "createdAt": datetime.fromtimestamp(at, timezone.utc).isoformat(),
                          "data": [{"key": key, "value": value} for key, value in fields.items()]}).encode()
        self.archive.ingest("tesla_V", 0, offset, VIN.encode(), raw)

    def test_allowlist_units_and_latest_invalid(self):
        now = time.time()
        self.ingest(0, now - 20, {"Soc": {"doubleValue": 60}, "VehicleSpeed": {"doubleValue": 10}, "Location": {"latitude": 37, "longitude": 127}})
        fields = {row["key"]: row for row in snapshot(self.archive, VIN, now)["fields"]}
        self.assertAlmostEqual(fields["VehicleSpeed"]["value"], 16.09344)
        self.assertNotIn("Location", fields)
        self.ingest(1, now - 10, {"Soc": {"invalid": True}})
        current = {row["key"]: row for row in snapshot(self.archive, VIN, now)["fields"]}
        self.assertIsNone(current["Soc"]["value"])
        self.assertEqual(current["Soc"]["status"], "invalid")

    def test_old_values_are_not_current(self):
        now = time.time()
        self.ingest(0, now - 121, {"Soc": {"doubleValue": 60}})
        soc = snapshot(self.archive, VIN, now)["fields"][0]
        self.assertEqual(soc["status"], "stale")
        self.assertIsNone(soc["value"])

    def test_scoped_key_cannot_read_history_or_another_vehicle(self):
        archive_key, dashboard_key = "a" * 40, "d" * 40
        server = HTTPServer(("127.0.0.1", 0), handler_for(self.archive, archive_key, {"ready": True}, dashboard_key, VIN))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        base = "http://127.0.0.1:" + str(server.server_port)
        try:
            for route, key, expected in [("/v1/dashboard?vin=" + VIN, archive_key, 401),
                                         ("/v1/dashboard?vin=" + OTHER, dashboard_key, 403),
                                         ("/v1/telemetry?vin=" + VIN, dashboard_key, 401)]:
                request = urllib.request.Request(base + route, headers={"Authorization": "Bearer " + key})
                with self.assertRaises(urllib.error.HTTPError) as failure:
                    urllib.request.urlopen(request)
                self.assertEqual(failure.exception.code, expected)
                failure.exception.close()
            request = urllib.request.Request(base + "/v1/dashboard?vin=" + VIN, headers={"Authorization": "Bearer " + dashboard_key})
            with urllib.request.urlopen(request) as response:
                result = json.load(response)
                self.assertEqual(len(result["fields"]), 4)
                self.assertNotIn("payloads", result)
                self.assertNotIn("vin", result)
            with urllib.request.urlopen(base + "/dashboard") as response:
                self.assertIn("frame-ancestors 'none'", response.headers["Content-Security-Policy"])
                self.assertNotIn(archive_key.encode(), response.read())
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_dashboard_key_must_be_distinct_and_scoped(self):
        with self.assertRaises(ValueError):
            handler_for(self.archive, "a" * 40, {}, "a" * 40, VIN)
        with self.assertRaises(ValueError):
            handler_for(self.archive, "a" * 40, {}, "d" * 40, "")


if __name__ == "__main__":
    unittest.main()
