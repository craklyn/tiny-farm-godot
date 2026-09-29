import contextlib
import io
import sys
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib.error import URLError

sys.path.insert(0, str(Path(__file__).parent))
import itch_page_sync


class ItchPageSyncTests(unittest.TestCase):
    def test_markdown_paragraph_wrap_matches_public_text(self):
        source = "A wrapped\nparagraph.\n\n### Controls\n- **Tap** a tile"
        self.assertEqual(itch_page_sync.markdown_visible_text(source),
                         "A wrapped paragraph.\nControls\nTap a tile")

    def test_comparison_reports_a_changed_description_and_paste_text(self):
        matches, report = itch_page_sync.comparison("**Tiny Farm**\n\nPlant seeds.", "Tiny Farm\nWater seeds.")
        self.assertFalse(matches)
        self.assertIn("-Water seeds.", report)
        self.assertIn("+Plant seeds.", report)

    def test_public_description_stops_after_a_normal_br_tag(self):
        html = ('<div class="formatted_description">First line<br>Second line</div>'
                '<p>Text outside the description</p>')
        self.assertEqual(itch_page_sync.public_description(html), "First line\nSecond line")

    def test_fetch_failure_prints_the_text_to_paste(self):
        page = Path(self.id().replace(".", "_") + ".md")
        self.addCleanup(page.unlink, missing_ok=True)
        page.write_text("## Description\n\nCopy for the page.\n", encoding="utf-8")
        output = io.StringIO()
        with patch.object(itch_page_sync, "fetch_public_page", side_effect=URLError("DNS failed")), contextlib.redirect_stderr(output):
            result = itch_page_sync.main(["--page", str(page)])
        self.assertEqual(result, 1)
        self.assertIn("Store-page sync failed", output.getvalue())
        self.assertIn("Text to paste into itch.io:\n\nCopy for the page.", output.getvalue())

    def test_live_mode_refuses_a_source_that_has_other_store_page_sections(self):
        page = Path(self.id().replace(".", "_") + ".md")
        self.addCleanup(page.unlink, missing_ok=True)
        page.write_text("## Project settings\n\nTitle\n\n## Description\n\nCopy for the page.\n", encoding="utf-8")
        with self.assertRaisesRegex(RuntimeError, "refuses to publish only the Description section"):
            itch_page_sync.live_sync("https://example.invalid", "Copy for the page.", page)

    def test_live_refusal_prints_the_text_to_paste(self):
        page = Path(self.id().replace(".", "_") + ".md")
        self.addCleanup(page.unlink, missing_ok=True)
        page.write_text("## Project settings\n\nTitle\n\n## Description\n\nCopy for the page.\n", encoding="utf-8")
        output = io.StringIO()
        with contextlib.redirect_stderr(output):
            result = itch_page_sync.main(["--page", str(page), "--live"])
        self.assertEqual(result, 1)
        self.assertIn("refuses to publish only the Description section", output.getvalue())
        self.assertIn("Text to paste into itch.io:\n\nCopy for the page.", output.getvalue())

    def test_login_challenge_detection_catches_urls_and_embedded_widgets(self):
        self.assertTrue(itch_page_sync.sign_in_challenge_detected(
            "https://itch.io/login", "Please complete the hCaptcha challenge."))
        self.assertTrue(itch_page_sync.sign_in_challenge_detected(
            "https://itch.io/two-factor", "Enter your code."))
        self.assertTrue(itch_page_sync.sign_in_challenge_detected(
            "https://itch.io/login", "", '<iframe src="https://challenges.cloudflare.com/widget"></iframe>'))
        self.assertFalse(itch_page_sync.sign_in_challenge_detected(
            "https://itch.io/dashboard", "Tiny Farm dashboard"))

    def test_login_requires_a_recognised_signed_in_page(self):
        self.assertTrue(itch_page_sync.successful_post_login("https://itch.io/", 1))
        self.assertTrue(itch_page_sync.successful_post_login("https://itch.io/dashboard", 1))
        self.assertFalse(itch_page_sync.successful_post_login("https://itch.io/login", 1))
        self.assertFalse(itch_page_sync.successful_post_login("https://itch.io/unknown", 1))
        self.assertFalse(itch_page_sync.successful_post_login("https://itch.io/", 0))

    def test_unrecognised_login_state_prints_paste_safe_failure(self):
        failure = itch_page_sync.sign_in_failure_message(
            "https://itch.io/login", "", "", 0)
        self.assertIn("recognised signed-in page", failure)
        self.assertIn("Paste the text below", failure)


if __name__ == "__main__":
    unittest.main()
