#!/usr/bin/env python3
"""The art tool a queue worker calls mid-session (S-37): a stdio MCP server.

The drain starts one per tier-1+ build session (hq/execution.py attaches it to
the Codex or Claude CLI). It runs outside the worker's sandbox, so it can reach
the art service, but its argv names only the card, paths and the run — it reads
the key itself from the .env files it is pointed at, and nothing it returns or
writes contains the key. All the work is hq/art_requests.py's; this file is the
protocol: newline-delimited JSON-RPC 2.0 with initialize, tools/list, tools/call
and ping. After each call it writes the session's record, which the drain reads
when the session ends to put the note (and any budget hold) on the card.
"""
import argparse
import json
import os
import sys
import traceback

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import art_requests  # noqa: E402

PROTOCOL = "2025-06-18"
_money = art_requests._money

TOOL_LIST = [
    {"name": "generate_art",
     "description": (
         "Generate pixel art with Retro Diffusion for this work card and save the raw PNGs "
         "under assets/raw/ in your worktree. Each call is priced first and refused, generating "
         f"nothing, if it would take this card past {_money(art_requests.CARD_CAP_USD)} or the "
         f"studio past {_money(art_requests.DAY_CAP_USD)} today. Returns the file paths, the cost "
         "and what is left. Call again with a better prompt if the result is wrong."),
     "inputSchema": {
         "type": "object", "additionalProperties": False,
         "required": ["what", "prompt", "width", "height"],
         "properties": {
             "what": {"type": "string", "description": "Short lowercase slug naming the subject, e.g. tomato-ripe"},
             "prompt": {"type": "string", "description": "What to draw, at most 2000 characters"},
             "width": {"type": "integer", "minimum": 16, "maximum": 512,
                       "description": "Pixels; sprites 64+, generate at 4x the cell"},
             "height": {"type": "integer", "minimum": 16, "maximum": 512},
             "num_images": {"type": "integer", "minimum": 1, "maximum": art_requests.MAX_IMAGES,
                            "description": "Candidates to generate (default 1); each is charged"},
             "prompt_style": {"type": "string",
                              "description": f"Retro Diffusion style (default {art_requests.DEFAULT_STYLE})"},
             "palette": {"type": "array", "items": {"type": "string", "pattern": "^#[0-9a-fA-F]{6}$"},
                         "description": "Palette lock, #rrggbb colours from docs/design/09-art-direction.md"},
             "input_image": {"type": "string", "description": "Path of a PNG inside the worktree to start from"},
             "seed": {"type": "integer"},
         }}},
    {"name": "art_budget",
     "description": "What this card and the studio have spent on art today, and what one more call may cost.",
     "inputSchema": {"type": "object", "properties": {}, "additionalProperties": False}},
]


class Server:
    def __init__(self, card, tree, attempt, key_files, rd=None):
        self.card, self.tree, self.attempt = card, tree, attempt
        self.key_files, self.rd = tuple(key_files), rd
        self.art = art_requests.new_session()

    # -- tools ---------------------------------------------------------------

    def generate_art(self, arguments):
        outcome = art_requests.generate_one(self.card, arguments, self.tree, self.key_files,
                                            rd=self.rd, day=self.art["day"])
        art_requests.note_call(self.art, outcome)
        art_requests.save_session(self.attempt, self.art)
        return reply(outcome), outcome["status"] != "generated"

    def art_budget(self, _arguments):
        try:
            b = art_requests.budget(self.card, self.art["day"])
        except (OSError, ValueError, AttributeError):
            return "The record of art spending could not be read; generate_art will refuse.", True
        return (f"This card has spent {_money(b['card_spent'])} of its {_money(b['card_cap'])}; the "
                f"studio has spent {_money(b['day_spent'])} of today's {_money(b['day_cap'])}. "
                f"A call may cost up to {_money(b['remaining'])}."), False

    # -- protocol ------------------------------------------------------------

    def handle(self, msg):
        """One JSON-RPC message in, the response out (None for a notification)."""
        if not isinstance(msg, dict):
            return _error(None, -32600, "Invalid request")
        mid, method = msg.get("id"), msg.get("method")
        if mid is None:
            return None                                  # notifications need no answer
        params = msg.get("params") or {}
        if method == "initialize":
            return _result(mid, {"protocolVersion": params.get("protocolVersion") or PROTOCOL,
                                 "capabilities": {"tools": {"listChanged": False}},
                                 "serverInfo": {"name": "tiny-farm-art", "version": "1"}})
        if method == "ping":
            return _result(mid, {})
        if method == "tools/list":
            return _result(mid, {"tools": TOOL_LIST})
        if method == "tools/call":
            name, arguments = params.get("name"), params.get("arguments") or {}
            tool = {"generate_art": self.generate_art, "art_budget": self.art_budget}.get(name)
            if tool is None:
                return _error(mid, -32602, f"Unknown tool: {name}")
            try:
                text, is_error = tool(arguments)
            except Exception as exc:  # noqa: BLE001 - the session must keep its tool
                traceback.print_exc(file=sys.stderr)
                text, is_error = f"The art tool failed ({type(exc).__name__}); nothing was generated.", True
            return _result(mid, {"content": [{"type": "text", "text": text}], "isError": is_error})
        return _error(mid, -32601, f"Method not found: {method}")

    def serve(self, stdin, stdout):
        for line in stdin:
            if not line.strip():
                continue
            try:
                msg = json.loads(line)
            except ValueError:
                response = _error(None, -32700, "Parse error")
            else:
                response = self.handle(msg)
            if response is not None:
                stdout.write(json.dumps(response) + "\n")
                stdout.flush()


def reply(outcome):
    """What the worker reads back from one generate_art call."""
    status = outcome["status"]
    if status == "generated":
        text = (f"Generated {len(outcome['images'])} image(s) for {_money(outcome['dollars'])}: "
                + ", ".join(outcome["images"]) + f" (metadata {outcome['meta']}).")
        if "remaining" in outcome:
            text += (f" This card has now spent {_money(outcome['card_spent'])} of its "
                     f"{_money(outcome['card_cap'])}; the next call may cost up to "
                     f"{_money(outcome['remaining'])}.")
        return text
    if status == "refused":
        return (f"Nothing was generated. {outcome['reason']} After this session the card is held "
                "for the chief of staff to decide whether it may spend more; finish the rest of "
                "the card and say in your reply what is still waiting for art.")
    reason = outcome["reason"].rstrip(".")
    reason = reason[:1].upper() + reason[1:]
    if status == "rejected":
        return f"Nothing was generated or charged. {reason}."
    return f"Nothing was generated. {reason}."


def _result(mid, result):
    return {"jsonrpc": "2.0", "id": mid, "result": result}


def _error(mid, code, message):
    return {"jsonrpc": "2.0", "id": mid, "error": {"code": code, "message": message}}


def build(argv, rd=None):
    """The server for one session, from the argv the drain gives it
    (art_requests.mcp_server). `rd` stands in for tools/rd_client.py in tests."""
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--card", required=True)
    ap.add_argument("--title", default="")
    ap.add_argument("--cap", type=float, default=art_requests.CARD_CAP_USD)
    ap.add_argument("--tree", required=True)
    ap.add_argument("--run", default="byhand")
    ap.add_argument("--attempt", required=True)
    ap.add_argument("--store", required=True)
    ap.add_argument("--key-file", action="append", default=[])
    args = ap.parse_args(argv)
    art_requests.STORE = args.store
    card = {"id": args.card, "title": args.title, "art_cap_usd": args.cap, "run": args.run}
    return Server(card, os.path.realpath(args.tree), args.attempt, args.key_file, rd=rd)


def main(argv=None):
    server = build(argv)
    # The protocol owns stdout; anything else printed goes to stderr.
    out, sys.stdout = sys.stdout, sys.stderr
    server.serve(sys.stdin, out)


if __name__ == "__main__":
    main()
