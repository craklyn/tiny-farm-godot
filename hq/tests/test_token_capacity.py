"""Unpriced model sessions still count against an item's autonomy budget."""

import json
import os
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
import drain  # noqa: E402


class TokenCapacityTests(unittest.TestCase):
    def test_unpriced_worker_and_checker_trip_token_cap(self):
        with tempfile.TemporaryDirectory() as root:
            run = os.path.join(root, "run")
            os.mkdir(run)
            for phase, count, fresh in (("work", 900_000, 90_000),
                                        ("check", 200_000, 20_000)):
                with open(os.path.join(run, f"wtest-drain-{phase}.json"), "w", encoding="utf-8") as sink:
                    json.dump({"usage": {"tokens": count, "fresh": fresh,
                                          "list_usd": None}}, sink)
            with patch.object(drain, "WORKERS", root):
                item = {"id": "wtest"}
                self.assertEqual(drain._item_spend("wtest"), (0.0, 1, 1_100_000, 110_000))
                self.assertIn("1,100,000 model tokens", drain.item_capacity_reason(item))
                item["token_cap"] = 1_500_000
                self.assertEqual(drain.item_capacity_reason(item), "")
                item["fresh_token_cap"] = 100_000
                self.assertIn("110,000 fresh model tokens", drain.item_capacity_reason(item))


if __name__ == "__main__":
    unittest.main()
