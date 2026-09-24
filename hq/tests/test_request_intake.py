"""Request intake keeps Daniel's words and a durable link across reopening."""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))
import work
from test_work import fake_host


class RequestIntakeTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        work.bind(fake_host(self.temp.name), sanitize=False)

    def tearDown(self):
        self.temp.cleanup()

    def test_submit_retry_discuss_and_reopen(self):
        words = "Could we change the crop work priority?\nThe seeds are hard to reach."
        body = {"words": words, "kind": "priority", "request_id": "request-12345678"}
        first = work.api_post("/api/work/request", body)
        self.assertEqual(first["source_message"], words)
        self.assertEqual(first["owner"], "claude")  # fallback when Priya is absent
        self.assertEqual(first["tier"], 0)
        self.assertEqual(first["state"], "doing")
        self.assertEqual(next(i for i in work.snapshot()["items"] if i["id"] == first["id"])["source_message"], words)
        self.assertEqual(work.api_post("/api/work/request", body)["id"], first["id"])
        self.assertEqual(len(work.items()), 1)
        self.assertIn("error", work.api_post("/api/work/request", {
            **body, "words": "different words"}))

        # A discussion remains attached to the card; no decision is created.
        work.api_post("/api/work/respond", {"id": first["id"], "message": "Please explain the order."})
        saved = work.load_item(first["id"])
        self.assertEqual(saved["conversation"][-1]["text"], "Please explain the order.")
        self.assertEqual(len(work.items()), 1)
        self.assertIn("error", work.api_post("/api/work/reopen", {
            "id": first["id"], "words": "Try again", "request_id": "request-87654321"}))

        saved["state"] = "dropped"
        work.save_item(saved)
        reopened = work.api_post("/api/work/reopen", {
            "id": first["id"], "words": "Please revisit the order.",
            "request_id": "request-87654321"})
        self.assertEqual(reopened["parent"], first["id"])
        self.assertEqual(reopened["reopens"], first["id"])
        self.assertEqual(next(i for i in work.snapshot()["items"] if i["id"] == reopened["id"])["parent"], first["id"])
        self.assertEqual(work.load_item(first["id"])["state"], "dropped")
        self.assertEqual(work.api_post("/api/work/reopen", {
            "id": first["id"], "words": "Please revisit the order.",
            "request_id": "request-87654321"})["id"], reopened["id"])
        self.assertEqual(len(work.items()), 2)


if __name__ == "__main__":
    unittest.main()
