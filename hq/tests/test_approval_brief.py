#!/usr/bin/env python3
"""A change held for Daniel's yes is explained in his words, and its exact
wording can be read before he answers (2026-09-28: "What does the title mean?")."""
from pathlib import Path
import sys
import types
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import server
import work

ORG = {"employees": [{"id": "tomas", "name": "Tomás Herrera"}]}
PATCH = """diff --git a/docs/design/06-bots-and-training.md b/docs/design/06-bots-and-training.md
index 1111111..2222222 100644
--- a/docs/design/06-bots-and-training.md
+++ b/docs/design/06-bots-and-training.md
@@ -10,2 +10,2 @@
 The pace row sits first on the shelf.
-The player buys pace once for 150 gold.
+A moving Mark III sits beside the chevrons; steps two and three are sold separately.
"""


FILES = ["docs/design/06-bots-and-training.md", "docs/DECISION_LOG.md"]


def ruling_card(held="it changes docs/design/06-bots-and-training.md, " + work.APPROVAL_HOLD):
    return {"id": "wa0bea812648", "owner": "tomas", "state": "for_review", "tier": 1,
            "ruling_id": "Q-131",
            "title": "Act on your ruling: The Mark III learning shop — you chose Show a moving Mark III beside the chevrons",
            "result": "Recorded Daniel's ruling in the design documents.\n\nMore detail.\n" + work.FOLLOW_MARK + "\n{}",
            "diff": {"applied": False, "files": FILES,
                     "why_not_landed": held},
            "attempt_outcome": {"id": "a1", "status": "complete",
                                "candidate": {"files": {"docs/design/06-bots-and-training.md": "blob"}}},
            "check": {"read": True, "verdict": "pass", "complete": True, "findings": [],
                      "attempt_id": "a1", "summary": "The ruling is consistently recorded."}}


class ApprovalBrief(unittest.TestCase):
    def test_a_ruling_card_asks_in_plain_words(self):
        brief = work.approval_brief(ruling_card(), ORG)
        self.assertEqual(brief["question"],
                         "Add Tomás's write-up of your Q-131 ruling (you chose: Show a moving Mark III "
                         "beside the chevrons) to the bots and training design doc and the decision log?")
        self.assertEqual(brief["summary"], "Recorded Daniel's ruling in the design documents.")
        self.assertEqual([f["name"] for f in brief["files"]],
                         ["the bots and training design doc", "the decision log"])
        self.assertTrue(brief["why"].startswith("The reviewer read it and found nothing wrong"))
        self.assertIn("record your direction", brief["reason"])
        self.assertIn("can be undone later", brief["yes"])
        self.assertEqual(brief["changes_link"], "/work-change/wa0bea812648")
        many = ruling_card()
        many["diff"]["files"] = FILES + ["docs/DESIGNER_QUEUE.md", "docs/design/14-training-workbench.md"]
        long = work.approval_brief(many, ORG)
        self.assertTrue(long["question"].endswith("to the design docs?"))
        self.assertEqual(len(long["files"]), 4)
        for text in brief.values():
            self.assertNotIn("undoing a commit", str(text))

    def test_cards_held_under_the_old_wording_are_still_his(self):
        old = "it changes docs/design/06-bots-and-training.md, which undoing a commit would not put back the way it was"
        self.assertTrue(work.landing_awaits_approval(ruling_card(old)))
        self.assertIsNotNone(work.approval_brief(ruling_card(old), ORG))

    def test_only_a_change_held_for_his_yes_gets_a_brief(self):
        card = ruling_card()
        card["check"]["verdict"] = "concerns"
        self.assertIsNone(work.approval_brief(card, ORG))

    def test_the_exact_changes_are_readable(self):
        files = server._parse_patch(PATCH)
        self.assertEqual(files[0]["path"], "docs/design/06-bots-and-training.md")
        self.assertEqual([k for k, _ in files[0]["lines"]], ["gap", "ctx", "del", "add"])
        fake_drain = types.SimpleNamespace(load_patch=lambda _id: PATCH)
        with patch.object(work, "load_item", return_value=ruling_card()), \
             patch.object(server, "load_org", return_value=ORG), \
             patch.dict(sys.modules, {"drain": fake_drain}):
            code, page = server.work_change_page("wa0bea812648")
        self.assertEqual(code, 200)
        self.assertIn("What Tomás changed", page)
        self.assertLess(page.index("Files changed"), page.index("class=diff"))
        self.assertIn("<span class=addn>+1</span> <span class=deln>−1</span>", page)
        self.assertIn("the bots and training design doc", page)
        self.assertIn('class=del>The player buys pace once for 150 gold.', page)
        self.assertIn("class=add>A moving Mark III sits beside the chevrons", page)
        self.assertEqual(server.work_change_page("../../etc")[0], 404)


if __name__ == "__main__":
    unittest.main()
