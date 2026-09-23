import json
import tempfile
import unittest
from pathlib import Path
from store import Archive

VIN = "LRWYGCEK0NC000001"
OTHER = "LRWYGCEK0NC000002"


def payload(vin=VIN, value=40):
    return json.dumps({"vin": vin, "createdAt": "2026-01-01T10:00:00Z",
                       "data": [{"key": "Soc", "value": {"doubleValue": value}}]}).encode()


class ArchiveTests(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
