#!/usr/bin/env python3
"""`hq/card.py` works a card through HQ's API, never by writing the file (Q-125 a)."""
import contextlib
import io
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import card  # noqa: E402
import server  # noqa: E402


class CardCommand(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="hq-card-command-")
        self.saved = (server.DATA, server.work.WORK, server.work.HOST)
        server.DATA = self.tmp
        os.makedirs(os.path.join(self.tmp, "work"))
        Path(self.tmp, "org.json").write_text(json.dumps({"employees": [{"id": "claude"}]}))
        server.work.bind(server, sanitize=False)
        Path(self.tmp, "work", "w0000000000d.json").write_text(json.dumps({
            "id": "w0000000000d", "title": "A card", "owner": "claude", "tier": 1,
            "state": "waiting_session", "created_ts": 1}))
        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        self.serving = True
        self.url = f"http://127.0.0.1:{self.httpd.server_address[1]}"

    def stop(self):
        if self.serving:
            self.httpd.shutdown()
            self.httpd.server_close()
            self.serving = False

    def tearDown(self):
        self.stop()
        server.DATA, server.work.WORK, server.work.HOST = self.saved
        shutil.rmtree(self.tmp, ignore_errors=True)

    def cli(self, *args):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = card.main(["--url", self.url, *args])
        return code, out.getvalue() + err.getvalue()

    def stored(self):
        return json.loads(Path(self.tmp, "work", "w0000000000d.json").read_text())

    def test_claim_release_and_a_refused_close_go_through_the_api(self):
        code, said = self.cli("claim", "w0000000000d", "--by", "Codex session", "--minutes", "30")
        self.assertEqual(code, 0, said)
        self.assertIn("worked by Codex session until", said)
        self.assertEqual(self.stored()["outside_claim"]["by"], "Codex session")
        code, said = self.cli("claim", "w0000000000d", "--by", "Another session")
        self.assertEqual(code, 2)
        self.assertIn("Refused: Work card w0000000000d is being worked by Codex session", said)
        code, said = self.cli("close", "w0000000000d", "--by", "Codex session", "--sha", "not-a-sha",
                              "--ci-run", "1", "--result", "Some result that is long enough.")
        self.assertEqual(code, 2)
        self.assertIn("hexadecimal SHA", said)
        self.assertEqual(self.stored()["state"], "waiting_session", "a refused close changes nothing")
        code, said = self.cli("release", "w0000000000d", "--by", "Codex session")
        self.assertEqual(code, 0, said)
        self.assertNotIn("outside_claim", self.stored())
        code, said = self.cli("claim", "w-bad", "--by", "Codex session")
        self.assertEqual(code, 2)
        self.assertIn("work card id", said)

    def test_an_unreachable_hq_is_reported_not_worked_around(self):
        self.stop()
        code, said = self.cli("claim", "w0000000000d", "--by", "Codex session")
        self.assertEqual(code, 2)
        self.assertIn("HQ is not reachable", said)
        self.assertNotIn("outside_claim", self.stored())


if __name__ == "__main__":
    unittest.main()
