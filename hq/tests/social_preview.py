#!/usr/bin/env python3
"""Isolated social-page preview: no background jobs, account reads or live writes.

python3 hq/tests/social_preview.py --data /tmp/social-preview-data --port 8643 \
    --media /home/daniel/dev/tiny-farm-godot-main/video
"""
import argparse
import json
import os
from pathlib import Path
import sys
from http.server import ThreadingHTTPServer

HQ = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HQ))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data", required=True)
    parser.add_argument("--media", required=True)
    parser.add_argument("--port", type=int, default=8643)
    args = parser.parse_args()
    data = Path(args.data).resolve()
    # The preview can only create records in a clearly temporary directory.
    if not data.is_relative_to(Path("/tmp")) or data == Path("/tmp"):
        parser.error("Preview data must have its own directory under /tmp.")
    data.mkdir(parents=True, exist_ok=True)
    (data / ".hq-store").write_text("Isolated social preview; not the live HQ store.\n")
    os.environ.update(HQ_DATA_ROOT=str(data), HQ_USER_WORKSPACE_ROOT=str(HQ.parent),
                      HQ_MAIN_ROOT=str(HQ.parent), HQ_SOCIAL_MEDIA_ROOT=str(Path(args.media).resolve()),
                      HQ_SOCIAL_PREVIEW="1")
    os.environ.pop("HQ_REQUIRE_EXPLICIT_ROOTS", None)
    import server
    # Scratch data contains only new records; checked-in configuration is read from code.
    server.cfg = lambda *parts: str(HQ / "data" / Path(*parts))
    server.work.bind(server, sanitize=False)
    server.social.bind(server)

    class PreviewHandler(server.Handler):
        def do_GET(self):
            path = self.path.split("?")[0]
            if path in ("/", "/index.html", "/api/org", "/api/surface", "/api/health", "/api/social") or path.startswith(("/static/", "/api/social/", "/social-media/", "/social-art/", "/api/work/", "/api/doc/")):
                return super().do_GET()
            return self._send(503, {"error":"This isolated preview does not read studio status or external accounts.", "available":False})

        def do_POST(self):
            if self.path.split("?")[0].startswith("/api/social/"):
                return super().do_POST()
            return self._send(403, {"error":"Only social-page changes are enabled in this isolated preview."})

    httpd = ThreadingHTTPServer(("127.0.0.1", args.port), PreviewHandler)
    print(json.dumps({"url":f"http://127.0.0.1:{httpd.server_port}/#/social", "data":str(data), "media":str(Path(args.media).resolve()), "preview":True}), flush=True)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
