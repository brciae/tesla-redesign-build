import importlib.util
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("navigation_quality_review", Path(__file__).with_name("navigation-quality-review.py"))
review = importlib.util.module_from_spec(spec)
spec.loader.exec_module(review)


class QualityReviewTests(unittest.TestCase):
    def test_counts_and_export_privacy(self):
        rows = [dict(vin="PRIVATE-A", at=t, navigation=True, text="PRIVATE-PLACE" * 5) for t in [0, 5, 30]]
        rows += [dict(vin="PRIVATE-B", at=6, navigation=True, text=rows[0]["text"])]
        result = review.audit(map(json.dumps, rows))
        self.assertEqual(result["navigation_starts"], 4)
        self.assertEqual(result["duplicate_starts_within_20s"], 1)
        self.assertEqual(result["long_sentences"], 4)
        self.assertNotIn("PRIVATE", json.dumps(result))

    def test_invalid_and_non_navigation(self):
        rows = ["{", "[]", json.dumps(dict(navigation=False)),
                json.dumps(dict(navigation=True, text="안내", at=True, vin="A")),
                json.dumps(dict(navigation=True, text="안내", at=float("nan"), vin="A"))]
        result = review.audit(rows)
        self.assertEqual(result["invalid_rows"], 4)
        self.assertEqual(result["navigation_starts"], 0)

    def test_no_cross_vehicle_or_time_reversal_duplicate(self):
        rows = [dict(vin=v, at=t, navigation=True, text="좌회전하세요.") for v, t in [("A", 30), ("B", 31), ("A", 20), ("A", 50)]]
        self.assertEqual(review.audit(map(json.dumps, rows))["duplicate_starts_within_20s"], 0)


if __name__ == "__main__":
    unittest.main()
