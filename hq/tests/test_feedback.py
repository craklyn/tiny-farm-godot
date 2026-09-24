"""The public itch parser must preserve comment links and honest empty states."""

import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from feedback import parse_comments, read_feedback


class FeedbackTest(unittest.TestCase):
    def test_public_comment_and_reply(self):
        page = '''<div class="game_comments_widget"><div class="community_post_list_widget">
          <div id="post-6517027" class="community_post"><span class="post_author"><a>Player</a></span>
          <span class="post_date" title="2026-09-24 12:00:00"><a href="/post/6517027">today</a></span>
          <div class="post_body user_formatted"><p>Watering <b>stopped</b>.</p><p>After sleep.</p></div></div>
          <div id="post-6518019" class="community_post is_reply"><span class="post_author">Developer</span>
          <div class="post_body">Thanks for the report.</div></div></div></div>'''
        self.assertEqual(parse_comments(page), [
            {"author": "Player", "body": "Watering stopped.\nAfter sleep.",
             "date": "2026-09-24 12:00:00", "url": "https://itch.io/post/6517027"},
            {"author": "Developer", "body": "Thanks for the report.",
             "date": "", "url": "https://itch.io/post/6518019"},
        ])

    def test_empty_requires_the_real_comment_list(self):
        self.assertEqual(parse_comments('<div class="game_comments_widget"><div class="community_post_list_widget"></div></div>'), [])
        with self.assertRaises(ValueError):
            parse_comments('<h2>Leave a comment</h2>')

    def test_unreachable_itch_is_not_zero_feedback(self):
        with patch("feedback.urlopen", side_effect=OSError("offline")):
            result = read_feedback()
        self.assertEqual(result["status"], "unavailable")
        self.assertNotIn("checked_at", result)


if __name__ == "__main__":
    unittest.main()
