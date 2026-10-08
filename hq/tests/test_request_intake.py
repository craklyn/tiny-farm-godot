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

    def test_follow_up_carries_his_words(self):
        # 2026-10-07: the barn request's follow-up held only its title, so the
        # owner would have designed without the spec he wrote.
        words = "Add an industrial barn.\nCows store up to 2 units of milk; inside it is 6 wide by 4 tall."
        request = work.api_post("/api/work/request", {
            "words": words, "kind": "work", "request_id": "request-barn-0001"})
        org = work.HOST.load_org()
        child = work._file_follow_ups(request, [{
            "title": "Draft three directions for the barn", "owner": request["owner"],
            "tier": 0, "why": "Needs proposals first."}], org, cap_id="follow",
            message="Accepted the barn request.")[0]
        self.assertIn(words, work.load_item(child["id"])["ask"])

    def test_grandchild_brief_carries_his_words(self):
        # 2026-10-07: the barn's design card was filed from the conversation on
        # the request's follow-up, and its brief held neither the spec nor the
        # photo notes he had given.
        words = "Add an industrial barn.\nInside it is 6 wide by 4 tall."
        request = work.api_post("/api/work/request", {
            "words": words, "kind": "work", "request_id": "request-barn-0002"})
        org = work.HOST.load_org()
        child = work._file_follow_ups(request, [{
            "title": "Propose the barn", "owner": request["owner"], "tier": 0,
            "why": "Proposals first."}], org, cap_id="follow", message="Accepted.")[0]
        child = work.load_item(child["id"])
        child["conversation"] = [{"role": "daniel", "text": "The floors are warm terracotta tile."},
                                 {"role": child["owner"], "text": "Noted."}]
        work.save_item(child)
        grandchild = work._file_follow_ups(child, [{
            "title": "Write the barn proposal", "owner": child["owner"], "tier": 1,
            "why": "It needs files."}], org, cap_id="reply", message="Filed from the conversation.")[0]
        brief = work.lineage_brief(work.load_item(grandchild["id"]))
        self.assertIn(words, brief)
        self.assertIn("warm terracotta tile", brief)
        self.assertNotIn("Noted.", brief)
        # The child already carries the request in its ask, so it is not repeated.
        self.assertNotIn(words, work.lineage_brief(child))

        # 2026-10-07: the prototypes card was filed while the chapter it draws
        # from waited for his OK, so the artist's copy did not have it.
        child = work.load_item(child["id"])
        child["state"] = "for_review"
        child["diff"] = {"files": ["docs/design/17-barn.md"], "applied": False}
        work.save_item(child)
        patches = os.path.join(os.path.dirname(work.WORK), "patches")
        os.makedirs(patches, exist_ok=True)
        with open(os.path.join(patches, child["id"] + ".patch"), "w") as f:
            f.write("diff --git a/docs/design/17-barn.md b/docs/design/17-barn.md\n")
        brief = work.lineage_brief(work.load_item(grandchild["id"]))
        self.assertIn("docs/design/17-barn.md", brief)
        self.assertIn(child["id"] + ".patch", brief)


if __name__ == "__main__":
    unittest.main()
