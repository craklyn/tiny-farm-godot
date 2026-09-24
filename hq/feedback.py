"""Read public itch comments for Daniel's small feedback round-up.

The itch API does not expose comments. This reads the public game page only;
it never needs an account key and never posts to itch. A missing comment widget
or a failed request is unknown, not an empty list.
"""

from datetime import datetime, timezone
from html.parser import HTMLParser
from urllib.request import Request, urlopen

GAME_URL = "https://craklyn.itch.io/tiny-farm"


class CommentParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.stack = []
        self.widget = False
        self.list_seen = False
        self.posts = []
        self.post = None
        self.post_depth = 0
        self.author_depth = 0
        self.body_depth = 0
        self.skip_depth = 0

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        classes = set(attrs.get("class", "").split())
        if tag in ("script", "style"):
            self.skip_depth += 1
        if tag == "div":
            self.stack.append(classes)
            if "game_comments_widget" in classes:
                self.widget = True
            if self.widget and "community_post_list_widget" in classes:
                self.list_seen = True
            if self.list_seen and "community_post" in classes and attrs.get("id", "").startswith("post-"):
                post_id = attrs["id"][5:]
                if post_id.isdecimal():
                    self.post = {"author": "", "body": "", "date": "", "url": f"https://itch.io/post/{post_id}"}
                    self.post_depth = len(self.stack)
            if self.post and "post_body" in classes:
                self.body_depth = len(self.stack)
        elif tag == "span":
            self.stack.append(classes)
            if self.post and "post_author" in classes:
                self.author_depth = len(self.stack)
            if self.post and "post_date" in classes:
                self.post["date"] = attrs.get("title", "")
        elif tag in ("p", "br") and self.body_depth and self.post:
            self.post["body"] += "\n"

    def handle_endtag(self, tag):
        if tag in ("script", "style") and self.skip_depth:
            self.skip_depth -= 1
        if tag in ("div", "span") and self.stack:
            depth = len(self.stack)
            if tag == "div" and self.post and depth == self.post_depth:
                self.post["author"] = " ".join(self.post["author"].split())
                self.post["body"] = "\n".join(x.strip() for x in self.post["body"].splitlines() if x.strip())
                if self.post["author"] and self.post["body"]:
                    self.posts.append(self.post)
                self.post = None
            if depth == self.author_depth:
                self.author_depth = 0
            if depth == self.body_depth:
                self.body_depth = 0
            self.stack.pop()

    def handle_data(self, data):
        if self.skip_depth or not self.post:
            return
        if self.author_depth:
            self.post["author"] += data
        if self.body_depth:
            self.post["body"] += data


def parse_comments(page):
    parser = CommentParser()
    parser.feed(page)
    if not (parser.widget and parser.list_seen):
        raise ValueError("itch comments section was not found")
    return parser.posts


def read_feedback():
    try:
        request = Request(GAME_URL, headers={"User-Agent": "TinyFarmHQ/1.0 (public feedback read)"})
        with urlopen(request, timeout=8) as response:
            page = response.read(2_000_001)
            if len(page) > 2_000_000:
                raise ValueError("itch page exceeded size limit")
            comments = parse_comments(page.decode("utf-8"))
        return {"status": "checked", "checked_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                "source": GAME_URL, "comments": comments}
    except (OSError, UnicodeError, ValueError) as exc:
        return {"status": "unavailable", "source": GAME_URL, "comments": [],
                "reason": str(exc)[:180]}
