#!/usr/bin/env python3
"""Work a card from a session: claim it, renew or release the claim, close it with evidence.

This is how a session that HQ did not launch tells HQ about a card (Q-125 a).
It never edits a card file: every command goes through the running HQ, which
checks the evidence itself and saves the card in its own store.

  python3 hq/card.py claim   w0123456789a --by "Codex session"            # shows as working
  python3 hq/card.py claim   w0123456789a --by "Codex session"            # again = heartbeat
  python3 hq/card.py release w0123456789a --by "Codex session"
  python3 hq/card.py close   w0123456789a --by "Codex session" \\
      --sha 5ec460b --ci-run 36157944103 --result "What changed, in plain sentences."

``close`` is refused unless the commit is on origin/main and the CI run is the
tests workflow, finished with success on that commit or a later main.  The
card records who closed it and that no checker or Daniel approval was recorded.
A claim lapses on its own after ``--minutes`` (default 120) unless renewed.
"""

import argparse
import json
import os
import sys
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

DEFAULT_URL = os.environ.get("HQ_URL", "http://localhost:8642")


def post(url, path, payload):
    body = json.dumps(payload).encode()
    request = Request(url.rstrip("/") + path, data=body,
                      headers={"Content-Type": "application/json"})
    try:
        with urlopen(request, timeout=180) as reply:
            return json.loads(reply.read().decode() or "{}")
    except HTTPError as exc:
        try:
            return json.loads(exc.read().decode() or "{}")
        except ValueError:
            return {"error": f"HQ answered {exc.code}"}
    except URLError as exc:
        return {"error": f"HQ is not reachable at {url}: {exc.reason}"}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--url", default=DEFAULT_URL, help="HQ's address (default %(default)s)")
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("claim", "release", "close"):
        cmd = sub.add_parser(name)
        cmd.add_argument("id", help="the work card id, e.g. w0123456789a")
        cmd.add_argument("--by", required=True,
                         help="who is doing this, e.g. 'Codex session' (never Daniel or a checker)")
        if name == "claim":
            cmd.add_argument("--minutes", type=int, default=120,
                             help="how long the claim lasts unless renewed (default 120)")
        if name == "close":
            cmd.add_argument("--sha", required=True, help="the commit on origin/main that landed the work")
            cmd.add_argument("--ci-run", required=True, help="the tests workflow run id that passed on it")
            cmd.add_argument("--result", required=True, help="what changed, in plain sentences")
            cmd.add_argument("--note", default="", help="a one-line summary (defaults to the result's first line)")
    args = parser.parse_args(argv)
    payload = {"id": args.id, "by": args.by}
    if args.command == "claim":
        payload["seconds"] = args.minutes * 60
    if args.command == "close":
        payload.update(sha=args.sha, ci_run=args.ci_run, result=args.result, note=args.note)
    reply = post(args.url, f"/api/work/{args.command}", payload)
    if reply.get("error"):
        print(f"Refused: {reply['error']}", file=sys.stderr)
        return 2
    item = reply.get("item") or reply
    held = item.get("outside_claim") or {}
    if args.command == "close":
        landed = item.get("landed") or {}
        print(f"{item.get('id')} {item.get('state')} at {str(landed.get('sha', ''))[:12]} "
              f"by {landed.get('by', '')}")
    elif held:
        print(f"{item.get('id')} worked by {held.get('by')} until {held.get('expires')}")
    else:
        print(f"{item.get('id')} released")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
