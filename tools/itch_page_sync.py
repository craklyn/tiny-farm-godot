#!/usr/bin/env python3
"""Compare Tiny Farm's published itch.io description with its source copy.

Without --live this program only reads the public page.  Live mode is kept
separate because it requires the dedicated store-page account created by Daniel.
"""

from __future__ import annotations

import argparse
import difflib
import os
import re
import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.error import URLError
from urllib.request import Request, urlopen

DEFAULT_URL = "https://craklyn.itch.io/tiny-farm"
BLOCK_TAGS = {"p", "div", "br", "li", "h1", "h2", "h3", "h4", "h5", "h6"}
VOID_TAGS = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"}
LIVE_DESCRIPTION_HEADING = "Description"


def description_from_page_file(path: Path) -> str:
    """Return the Markdown below the Description heading, without internal notes."""
    text = path.read_text(encoding="utf-8")
    match = re.search(r"^## Description\s*$\n(.*?)(?=^## |\Z)", text,
                      flags=re.MULTILINE | re.DOTALL)
    if not match:
        raise ValueError(f"{path} has no '## Description' section")
    return match.group(1).strip()


def unpublished_sections(path: Path) -> list[str]:
    """Return source sections that a description-only editor cannot publish.

    `ITCH_PAGE.md` documents title, pricing, uploads, and embed settings as well
    as the public description.  Writing only the description would make a live
    run look like it synced the page while silently leaving those sections
    behind, so live mode must stop until it can update all of them.
    """
    headings = re.findall(r"^#{2,3}\s+(.+?)\s*$", path.read_text(encoding="utf-8"),
                          flags=re.MULTILINE)
    return [heading for heading in headings if heading != LIVE_DESCRIPTION_HEADING]


def markdown_visible_text(markdown: str) -> str:
    """Make the small Markdown subset used by the page comparable to HTML text."""
    visible_lines: list[str] = []
    paragraph: list[str] = []

    def finish_paragraph() -> None:
        if paragraph:
            visible_lines.append(" ".join(paragraph))
            paragraph.clear()

    for line in markdown.splitlines():
        line = line.strip()
        if not line:
            finish_paragraph()
            continue
        heading = re.match(r"^#{1,6}\s+(.+)$", line)
        list_item = re.match(r"^[-*+]\s+(.+)$", line)
        if heading or list_item:
            finish_paragraph()
            visible_lines.append((heading or list_item).group(1))
        else:
            paragraph.append(line)
    finish_paragraph()

    text = "\n".join(visible_lines)
    text = re.sub(r"!?(?:\[([^]]*)\])\([^)]*\)", r"\1", text)
    text = re.sub(r"[`*_]", "", text)
    return normalise_visible_text(text)


def normalise_visible_text(text: str) -> str:
    lines = [re.sub(r"\s+", " ", line).strip() for line in text.splitlines()]
    return "\n".join(line for line in lines if line)


class DescriptionHTMLParser(HTMLParser):
    """Extract text from itch.io's formatted-description element."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.depth: int | None = None
        self.parts: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        classes = dict(attrs).get("class", "") or ""
        if self.depth is None and "formatted_description" in classes.split():
            self.depth = 1
            return
        if self.depth is not None:
            if tag in BLOCK_TAGS:
                self.parts.append("\n")
            # HTMLParser reports a normal <br> as a start tag, not a
            # start-end tag. Void elements have no matching end tag, so they
            # must not become part of the nesting depth.
            if tag not in VOID_TAGS:
                self.depth += 1

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if self.depth is not None and tag in BLOCK_TAGS:
            self.parts.append("\n")

    def handle_endtag(self, tag: str) -> None:
        if self.depth is None:
            return
        if tag in BLOCK_TAGS:
            self.parts.append("\n")
        if tag in VOID_TAGS:
            return
        self.depth -= 1
        if self.depth == 0:
            self.depth = None

    def handle_data(self, data: str) -> None:
        if self.depth is not None:
            self.parts.append(data)

    def description(self) -> str:
        return normalise_visible_text("".join(self.parts))


def public_description(html: str) -> str:
    parser = DescriptionHTMLParser()
    parser.feed(html)
    parser.close()
    result = parser.description()
    if not result:
        raise ValueError("The public page has no formatted description to compare.")
    return result


def comparison(expected_markdown: str, published_text: str) -> tuple[bool, str]:
    expected = markdown_visible_text(expected_markdown)
    published = normalise_visible_text(published_text)
    if expected == published:
        return True, "The public itch.io description matches ITCH_PAGE.md. Nothing would be pasted."
    diff = "\n".join(difflib.unified_diff(
        published.splitlines(), expected.splitlines(), fromfile="public itch.io page",
        tofile="ITCH_PAGE.md", lineterm=""))
    return False, "The public itch.io description differs from ITCH_PAGE.md:\n" + diff


def fetch_public_page(url: str) -> str:
    request = Request(url, headers={"User-Agent": "Tiny-Farm-store-page-check/1.0"})
    with urlopen(request, timeout=30) as response:
        return response.read().decode(response.headers.get_content_charset() or "utf-8")


def sign_in_challenge_detected(url: str, page_text: str, page_html: str = "") -> bool:
    """Recognise a sign-in challenge from its URL, text, or embedded widget."""
    location = url.lower()
    text = re.sub(r"\s+", " ", page_text.lower())
    markup = page_html.lower()
    challenge_words = (
        "captcha", "recaptcha", "hcaptcha", "turnstile", "bot check",
        "two-factor", "two factor", "2fa", "one-time code", "one time code",
        "security challenge", "verify your identity", "verification code",
    )
    challenge_url_parts = ("/two-factor", "/2fa", "/captcha", "/challenge", "/verify")
    challenge_widgets = (
        "recaptcha", "hcaptcha", "turnstile", "challenges.cloudflare.com",
        "captcha-container", "challenge-form", "two-factor",
    )
    return (any(part in location for part in challenge_url_parts)
            or any(word in text for word in challenge_words)
            or any(widget in markup for widget in challenge_widgets))


def successful_post_login(url: str, signed_in_control_count: int) -> bool:
    """Allow only itch.io's signed-in navigation before opening the dashboard."""
    match = re.fullmatch(r"https://itch\.io(?:/(?:dashboard)?)?/?(?:[?#].*)?", url.lower())
    return bool(match) and signed_in_control_count > 0


def sign_in_failure_message(url: str, page_text: str, page_html: str,
                            signed_in_control_count: int) -> str | None:
    """Return the paste-safe failure for any post-login state that is not allowed."""
    if sign_in_challenge_detected(url, page_text, page_html):
        return ("itch.io requested a sign-in challenge, bot check, or two-factor prompt. "
                "Paste the text below into the page editor; the release did not bypass the prompt.")
    if not successful_post_login(url, signed_in_control_count):
        return ("itch.io did not reach a recognised signed-in page for the dedicated "
                "store-page account. Paste the text below into the page editor.")
    return None


def live_sync(url: str, description: str, page_file: Path) -> None:
    """Write the source Markdown through itch.io's editor, then verify the public page."""
    sections = unpublished_sections(page_file)
    if sections:
        raise RuntimeError(
            "Live store-page sync refuses to publish only the Description section. "
            "ITCH_PAGE.md also has these sections: " + ", ".join(sections) +
            ". Add support for every section before enabling ITCH_PAGE_LIVE_SYNC."
        )
    user = os.environ.get("ITCH_PAGE_USER")
    password = os.environ.get("ITCH_PAGE_PASSWORD")
    if not user or not password:
        raise RuntimeError("Live store-page sync needs ITCH_PAGE_USER and ITCH_PAGE_PASSWORD for the dedicated itch.io account.")
    try:
        from playwright.sync_api import sync_playwright
    except ImportError as error:
        raise RuntimeError("Live store-page sync needs Playwright. Install it before enabling ITCH_PAGE_LIVE_SYNC.") from error

    try:
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(headless=True)
            page = browser.new_page()
            page.goto("https://itch.io/login", wait_until="networkidle")
            page.locator('input[name="username"]').fill(user)
            page.locator('input[name="password"]').fill(password)
            page.locator('button[type="submit"], input[type="submit"]').first.click()
            page.wait_for_load_state("networkidle")
            body_text = page.locator("body").inner_text()
            page_html = page.content()
            signed_in_controls = page.locator('a[href="/dashboard"], a[href="/logout"], form[action="/logout"]').count()
            failure = sign_in_failure_message(page.url, body_text, page_html, signed_in_controls)
            if failure:
                raise RuntimeError(failure)
            page.goto("https://itch.io/dashboard", wait_until="networkidle")
            edit_link = page.locator('a[href*="/game/edit/"]').filter(has_text="Tiny Farm")
            if not edit_link.count():
                raise RuntimeError("Tiny Farm was not available in this account's itch.io dashboard. Paste the text below into the page editor.")
            edit_link.first.click()
            page.wait_for_load_state("networkidle")
            editor = page.locator('textarea[name="game[description]"]')
            if not editor.count():
                raise RuntimeError("The itch.io description editor was not found. Paste the text below into the page editor.")
            editor.fill(description)
            page.locator('input[type="submit"][value*="Save"], button:has-text("Save")').first.click()
            page.wait_for_load_state("networkidle")
            browser.close()
    except RuntimeError:
        raise
    except Exception as error:
        raise RuntimeError("The itch.io editor could not be updated. Paste the text below into the page editor.") from error

    matches, result = comparison(description, public_description(fetch_public_page(url)))
    if not matches:
        raise RuntimeError("The public itch.io page still differs after saving. Paste the text below into the page editor.\n" + result)
    print("The public itch.io description matches ITCH_PAGE.md after saving.")


def main(argv: list[str] | None = None) -> int:
    arguments = argparse.ArgumentParser(description=__doc__)
    arguments.add_argument("--page", type=Path, default=Path("ITCH_PAGE.md"))
    arguments.add_argument("--url", default=DEFAULT_URL)
    arguments.add_argument("--live", action="store_true", help="sign in and update the description")
    args = arguments.parse_args(argv)
    source = description_from_page_file(args.page)
    try:
        if args.live:
            live_sync(args.url, source, args.page)
            return 0
        matches, result = comparison(source, public_description(fetch_public_page(args.url)))
        print(result)
        if not matches:
            print("\nText that would be pasted into itch.io:\n\n" + source)
        return 0
    except (URLError, ValueError, RuntimeError) as error:
        print(f"Store-page sync failed: {error}", file=sys.stderr)
        print("\nText to paste into itch.io:\n\n" + source, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
