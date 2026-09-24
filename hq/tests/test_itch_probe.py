"""The itch probe must distinguish absent credentials, failure, and real counts."""
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import server


class ItchProbeTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.data = self.root / "data"
        self.data.mkdir()
        self.addCleanup(patch.stopall)
        patch.object(server, "DATA", str(self.data)).start()
        patch.object(server, "REPO", str(self.root)).start()
        patch.object(server, "USER_WORKSPACE", str(self.root)).start()
        patch.dict(os.environ, {"ITCH_API_KEY": ""}).start()

    def cached(self):
        path = self.data / "probes" / "itch_daily.json"
        return json.loads(path.read_text()) if path.exists() else None

    def test_no_key_removes_prior_reading_and_stays_absent(self):
        path = self.data / "probes" / "itch_daily.json"
        path.parent.mkdir()
        path.write_text('{"views_count": 10}')
        with patch.object(server, "urlopen") as fetch:
            server._poll_itch_daily()
        fetch.assert_not_called()
        self.assertIsNone(self.cached())
        reading = server.eval_measure({"kind": "probe_cache", "probe": "itch_daily",
                                       "field": "available"})
        self.assertIsNone(reading["value"])
        self.assertIn("not polled", reading["error"])

    def test_valid_response_records_only_supported_counts(self):
        payload = {"games": [{"url": "http://craklyn.itch.io/tiny-farm/",
                              "views_count": 17, "downloads_count": 3,
                              "purchases_count": 1}]}
        with patch.dict(os.environ, {"ITCH_API_KEY": "fixture-key"}), patch.object(
                server, "urlopen", return_value=io.BytesIO(json.dumps(payload).encode())) as fetch:
            server._poll_itch_daily()
        self.assertEqual(fetch.call_args.args[0].get_header("Authorization"), "Bearer fixture-key")
        doc = self.cached()
        self.assertEqual((doc["views_count"], doc["downloads_count"]), (17, 3))
        self.assertTrue(doc["available"])
        self.assertIn("polled_at", doc)
        self.assertNotIn("plays_count", doc)
        self.assertNotIn("fixture-key", json.dumps(doc))
        reading = server.eval_measure({"kind": "probe_cache", "probe": "itch_daily",
                                       "field": "available"})
        self.assertTrue(reading["value"])

    def test_wrong_key_is_an_error_without_counts(self):
        with patch.dict(os.environ, {"ITCH_API_KEY": "wrong"}), patch.object(
                server, "urlopen", side_effect=HTTPError("url", 401, "unauthorized", {}, None)):
            server._poll_itch_daily()
        self.assertIn("HTTP 401", self.cached()["error"])
        self.assertNotIn("views_count", self.cached())
        reading = server.eval_measure({"kind": "probe_cache", "probe": "itch_daily",
                                       "field": "available"})
        self.assertIsNone(reading["value"])
        self.assertIn("HTTP 401", reading["error"])

    def test_key_for_other_game_is_an_error(self):
        payload = {"games": [{"url": "https://someone.itch.io/other",
                              "views_count": 2, "downloads_count": 1}]}
        with patch.dict(os.environ, {"ITCH_API_KEY": "other"}), patch.object(
                server, "urlopen", return_value=io.BytesIO(json.dumps(payload).encode())):
            server._poll_itch_daily()
        self.assertIn("not found", self.cached()["error"])
        self.assertNotIn("views_count", self.cached())

    def test_storefront_definition_comes_from_code_with_separate_live_data(self):
        code = self.root / "code"
        (code / "data").mkdir(parents=True)
        current = {"platforms": [{"id": "itch-web", "requirements": [
            {"label": "Store analytics we can read", "check": {
                "kind": "probe_cache", "probe": "itch_daily", "field": "available"}}]}]}
        stale = {"platforms": [{"id": "itch-web", "requirements": [
            {"label": "Store analytics we can read", "check": {
                "kind": "file_exists", "path": "old-cache.json"}}]}]}
        (code / "data" / "platforms.json").write_text(json.dumps(current))
        (self.data / "platforms.json").write_text(json.dumps(stale))
        server._write_probe("itch_daily", {"available": True})
        with patch.object(server, "HQ_DIR", str(code)):
            requirement = server.platform_ladder()["platforms"][0]["requirements"][0]
        self.assertEqual(requirement["state"], "have")


if __name__ == "__main__":
    unittest.main()
