#!/usr/bin/env python3
"""Catch writing Daniel would have to decode, before it reaches the one person who cannot ask it what it means.

Daniel, 2026-09-04, reading a work card titled "Re-run the suites so each stamps
the commit it proved":

    "What are the suites? I think it's test suites, but I don't have enough
    context on this page to know. 'stamps' and 'proves' are terms of art, not
    literal? ... We need a way to eradicate all of this hard to handle text.
    It's only causing friction, and the friction is so severe that it's getting
    in way of the process."

**Why this is not a word list any more.** It was one until 2026-09-19 — 23 banned
terms, each with a plain replacement. That day a commit subject reached his
dashboard reading "The sim benchmark's target is a frame she would feel, not a
round number", and the check said nothing, because "frame" was not on the list.
His ruling:

    "I'm surprised a word list is a good solution. If I had a human coworker who
    used a couple weird words, I'd be explaining a principle to follow and check.
    Not a fixed set of words. There's tens of thousands of words that wouldn't be
    appropriate to use in an obscure way, so this can't scale properly."

So the rule is now checked the way a person would check it. `docs/WRITING.md` is
the principle and `docs/writing_rulings.json` is every call he has actually made,
kept as *shapes* of failure rather than as vocabulary; the two together brief a
model that reads each piece of text and answers as a careful colleague would.
There is no list to keep adding to, which is the point.

**A finding must quote the phrase it objects to, say why, and offer a plain
rewrite.** One with no quote is dropped unread. That is what keeps a judge from
drifting into taste-policing, and it means every failure arrives with its fix.

What it reads: the text fields that end up on screen — work-card titles, goal
statements, decision-card questions and options, pillar names and taglines — plus
the string literals in HQ's front-end code, plus a commit subject when asked.
Deliberately NOT: work-card briefs, persona prompts, code comments and design
docs, which are written for agents, for machines, or for a teammate looking
something up, and where a precise internal name is the right word.

    python3 tools/check_writing.py                  # judge every human-facing surface
    python3 tools/check_writing.py --verify         # offline: has everything been judged, and did it pass
    python3 tools/check_writing.py --subject FILE   # judge one commit subject (the commit-msg hook)
    python3 tools/check_writing.py --self-test      # replay every past ruling and prove the judge still agrees
    python3 tools/check_writing.py --list           # the rulings, as a table

**Every verdict is cached** in `docs/writing_verdicts.json`, keyed by the text and
by a fingerprint of the brief. So a re-run with nothing edited costs nothing and
cannot flip its own answer; editing `WRITING.md` or the rulings re-judges
everything, which is correct — the standard moved. CI runs `--verify`, which is
offline and deterministic: it fails when text has changed without being judged,
never because a model was in a different mood on a shared runner.

A line that genuinely needs an odd word says so with `plain-ok: <reason>` on it
(in code) or through a waiver in the rulings file (in data), and the waiver is
printed rather than hidden — an excuse nobody can see is indistinguishable from a
rule nobody applies.
"""
import argparse
import glob
import hashlib
import json
import os
import re
import subprocess
import sys
import shutil

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO, 'hq'))
import execution

RULINGS = os.path.join(REPO, "docs", "writing_rulings.json")
BRIEF = os.path.join(REPO, "docs", "WRITING.md")
CACHE = os.path.join(REPO, "docs", "writing_verdicts.json")
WAIVER = re.compile(r"plain-ok:\s*(\S.*)$")
# What an interpolated value looks like to the judge. A value stands in that gap
# on the screen, so leaving the gap empty would be the checker inventing a
# sentence the writer never wrote — see rendered_text.
VALUE_HERE = "…"
# The tags that put a line break on the screen. Their edges end a sentence.
BLOCK_TAG = re.compile(
    r"</?(?:h[1-6]|p|div|li|ul|ol|tr|td|th|table|section|article|header|footer|main"
    r"|nav|aside|form|pre|blockquote|details|summary|figcaption|figure|button|label"
    r"|legend|caption|option|dt|dd|br|hr)\b[^>]*>", re.I)
# The same gap on the data side: a goal's verdict sentence carries {unassured}
# and {total}, filled in by the page before it is read.
DATA_SLOT = re.compile(r"\{[a-z][a-z0-9_]*\}")

# Small and fast on purpose: this is a reading comprehension question with the
# standard supplied, not a reasoning problem, and it runs on every commit.
JUDGE_MODEL = "haiku"
BATCH = 25          # texts per call — one call for a whole sweep in most runs
CALL_TIMEOUT = 180

# Every field here is rendered to Daniel. The path is a dotted walk; `[]` means
# "every item in this list". Adding a field is how a new surface joins the check.
DATA_SOURCES = [
    ("hq/data/work/*.json", ["title"], "work card"),
    ("hq/data/goals/*.json", ["goals[].statement", "goals[].statement_short",
                              "goals[].why_it_matters",
                              "goals[].path_to_green.narrative",
                              "verdict_template.fire", "verdict_template.attention",
                              "verdict_template.unassured", "verdict_template.ok",
                              "verdict_template.nothing_for_you"], "pillar goal"),
    ("hq/data/decisions/*.json", ["title", "question", "why_now",
                                  "options[].label", "options[].detail",
                                  "options[].what", "options[].cost"], "decision card"),
    ("hq/data/pillars.json", ["pillars[].name", "pillars[].tagline",
                              "pillars[].question"], "pillar"),
]
CODE_SOURCES = ["hq/static/app.js", "hq/static/work.js", "hq/static/pillars.js",
                "hq/static/design.js", "hq/static/playtests.js", "hq/static/map.js",
                "hq/static/sprite.js"]

# Work cards that are finished are the company's record of what it did. Rewriting
# history to satisfy a rule written later would be dishonest, so the check reads
# only the cards still in front of him.
CLOSED_STATES = ("accepted", "dropped")


# --- the brief the judge is given ----------------------------------------------

def load_rulings(path=RULINGS):
    return json.load(open(path, encoding="utf-8"))


def brief_text(rulings=None):
    """`WRITING.md` plus every ruling, as one system prompt.

    The whole set goes in, every call. It is about three thousand tokens and the
    corpus grows by a handful of rulings a year, so retrieval would be machinery
    for a problem we do not have — and worse, it would rank by topic when what a
    judge needs is the near-misses on the line, which come from anywhere."""
    rulings = rulings or load_rulings()
    lines = [open(BRIEF, encoding="utf-8").read(), "", "# Calls already made", ""]
    for shape in rulings["shapes"]:
        lines.append(f"## {shape['shape']}")
        lines.append(shape["why_it_fails"])
        for r in shape["rulings"]:
            lines.append(f"- {r['verdict'].upper()}: “{r['text']}”")
            lines.append(f"  why: {r['why']}")
            lines.append(f"  instead: {r['instead']}")
        lines.append("")
    lines.append("## Ruled fine — do NOT flag anything like these")
    for r in rulings["ruled_fine"]:
        lines.append(f"- “{r['text']}”")
        lines.append(f"  why it is fine: {r['why']}")
    return "\n".join(lines)


def brief_fingerprint(rulings=None):
    """Changing the principle or the rulings invalidates every cached verdict,
    because the standard they were judged against moved."""
    h = hashlib.sha256()
    h.update(open(BRIEF, "rb").read())
    h.update(json.dumps(rulings or load_rulings(), sort_keys=True).encode())
    h.update(SYSTEM.encode())
    h.update(JUDGE_MODEL.encode())
    return h.hexdigest()[:16]


SYSTEM = """You are reviewing text that will be shown to one person: the founder of a small
game studio. He arrives cold, between other things, holding none of the project's
vocabulary and none of yesterday's conversation.

Your standard is the document below — the studio's writing rules, and every call
the founder has already made, grouped by the shape of the failure rather than by
vocabulary. Apply the principle. Do NOT treat the examples as a list of banned
words: a word that is wrong in one sentence is right in another, and the "ruled
fine" section exists to show you where the line actually sits. Flagging good
prose is a worse failure than missing a borderline case, because a check people
learn to ignore protects nobody.

TWO THINGS YOU ARE NOT DOING, and getting these wrong is the main way this check
becomes noise people learn to skip.

1. **This is not a style, tone or grammar review.** Do not flag passive voice, a
   hidden actor, wordiness, repetition, a missing call to action, a sentence that
   could be tighter, or anything you would merely have written differently. If a
   reader takes the meaning straight off the page, it is "ok" however you would
   have phrased it. The question you are answering is whether he would have to
   work out what a word or phrase MEANS, or go and ask someone.

   The one thing that is not a style question, though it looks like one: a
   sentence that lands only on a **second read** — a riddle, an inversion, a line
   arranged for effect where a plain statement belongs. He can get there, but he
   pays a re-read to do it, and the studio's rule 3 says that tax is payable in
   the game's own writing and never on a page someone works from. Judge those on
   what they cost the reader, not on whether the meaning is ultimately available.

2. **The studio's own names are not house vocabulary.** He coined them and uses
   them every day: the game's characters, machines, places, features and
   milestones — the Mark III and the mark-1, the Zoo, the Animation Lab and its
   loops, the coop, the bin, the overnight, phase 4, Q-numbers for design
   questions. A name for a thing in his own game or roadmap is a proper noun to
   him, not jargon. What you ARE looking for is internal *process* and
   *engineering* shorthand standing where an ordinary word exists — "provenance"
   for where it came from, "the suites" for the tests, "monitoring is landing" for
   a plan being written, "the look is holding" for nothing having changed.

These three ARE in scope, and none of them is a style question — each one leaves
the reader working out what was meant, which is the whole test:

  - a metaphor or clever construction standing where the plain fact belongs
    ("the one thing we cannot hear" for "players have no way to send feedback");
  - a bare pronoun — she, it, they — whose referent is not in that same sentence;
  - the internal mechanism named where the symptom belongs ("fits in a frame"
    for "makes the tablet stutter").

For each numbered text you are given, decide:
  "ok"          — a stranger would understand this. Most text should be this.
  "second-look" — understandable, but a word or construction is doing the reader
                  no favours. Worth raising, not worth blocking.
  "decode"      — the reader would have to work out what is meant, or ask someone.

Reply with JSON only: {"findings": [{"n": <number>, "verdict": "...",
"quote": "<the exact substring you object to, copied character for character>",
"why": "<one sentence, plain>", "instead": "<the same text rewritten plainly>"}]}

Omit any text you judge "ok" — report only second-look and decode. Every finding
MUST carry a quote copied exactly from the text; a finding without one is thrown
away unread.

%s"""


# --- reading the surfaces (unchanged in substance since 2026-09-04) ------------

def walk(doc, path):
    """One dotted field path -> every string it names. `[]` iterates a list."""
    head, _, rest = path.partition(".")
    if head.endswith("[]"):
        for item in (doc.get(head[:-2]) or []) if isinstance(doc, dict) else []:
            yield from walk(item, rest) if rest else ([item] if isinstance(item, str) else [])
        return
    if not isinstance(doc, dict):
        return
    got = doc.get(head)
    if rest:
        yield from walk(got or {}, rest)
    elif isinstance(got, str):
        yield got


def strings_in_js(text):
    """(line number, string literal) for the text a page actually renders.

    Comments are skipped on purpose: `docs/WRITING.md` rule 8 puts design
    rationale in comments, and that prose is written for whoever maintains the
    file. Only what can reach the screen is checked.

    A template literal's `${ }` is read as code, not as more of the string. The
    first version scanned from one backtick to the next, which meant a template
    written inside a conditional ended its parent early: HQ's pages are full of
    them, and the halves came back as texts like "s own note says its ramps" and
    ": esc(p2g.owner)} owns it". Those are not sentences anybody wrote, and a
    judge reading them objects to the checker rather than to the writing. So an
    expression is skipped the way the browser skips it — leaving `${}` behind,
    which `rendered_text` turns into the value a reader would see there — and any
    template nested inside it is reported as the separate string it is."""
    out, n = [], len(text)

    def read_quoted(i, line, quote):
        start = j = i + 1
        while j < n and text[j] != quote:
            if text[j] == "\\":
                j += 1
            j += 1
        body = text[start:j]
        out.append((line, body))
        return j + 1, line + body.count("\n")

    def read_template(i, line):
        opened, body, j = line, [], i + 1
        while j < n and text[j] != "`":
            if text[j] == "\\":
                body.append(text[j:j + 2]); j += 2; continue
            if text.startswith("${", j):
                body.append("${}")
                j, line = skip_code(j + 2, line, to_close=True)
                continue
            if text[j] == "\n":
                line += 1
            body.append(text[j]); j += 1
        out.append((opened, "".join(body)))
        return j + 1, line

    def read_regex(i, line):
        """Step over a /regex/, char class and all. Nothing in one is page text."""
        j, in_class = i + 1, False
        while j < n:
            ch = text[j]
            if ch == "\\":
                j += 2; continue
            if ch == "\n":
                break                      # a regex cannot span lines: not one
            if ch == "[":
                in_class = True
            elif ch == "]":
                in_class = False
            elif ch == "/" and not in_class:
                j += 1
                while j < n and text[j].isalpha():
                    j += 1                 # its flags
                return j, line
            j += 1
        return i + 1, line                 # unterminated: it was a division

    def skip_code(i, line, to_close=False):
        """Walk code. With `to_close`, stop just past the `}` that closes a `${`."""
        depth, prev = 0, ""
        while i < n:
            c = text[i]
            if c == "\n":
                line += 1; i += 1; continue
            if c == "/" and i + 1 < n and text[i + 1] == "/":
                while i < n and text[i] != "\n":
                    i += 1
                continue
            if c == "/" and i + 1 < n and text[i + 1] == "*":
                j = text.find("*/", i + 2)
                j = n if j < 0 else j + 2
                line += text.count("\n", i, j)
                i = j
                continue
            # A regex literal is not a string, and its quotes are not quotes.
            # `esc()` in app.js is written `.replace(/[&<>"']/g, …)`, and the
            # lone apostrophe inside that character class used to open a string
            # that ran on for hundreds of lines — every piece of text in the
            # file after line 42 was read paired with the wrong neighbour. The
            # usual heuristic tells a regex from a division: after a value you
            # are dividing, after an operator or an opening bracket you are not.
            if c == "/" and (prev == "" or prev in "(,=:[!&|?{};+-*%~^<>"):
                i, line = read_regex(i, line)
                prev = "/"
                continue
            if c in "'\"":
                i, line = read_quoted(i, line, c)
                prev = c
                continue
            if c == "`":
                i, line = read_template(i, line)
                prev = "`"
                continue
            if to_close:
                if c == "{":
                    depth += 1
                elif c == "}":
                    if not depth:
                        return i + 1, line
                    depth -= 1
            if not c.isspace():
                prev = c
            i += 1
        return i, line

    skip_code(0, 1)
    return out


def rendered_text(s):
    """What a person actually sees, out of a string that is mostly markup.

    The first version of this checked the raw literal and reported a CSS class
    called `g-orphan`, a field called `gate.total` and a local named `tier` — all
    of them invisible to any reader, none of them a writing problem. A check that
    cries wolf on identifiers is a check people learn to skip, which leaves the
    real ones exactly as unfound as before. So the markup and the interpolated
    code come out first, and only the words between the tags are read.

    An interpolated value leaves a placeholder rather than a hole. Deleting it
    outright turned "the last ${window} finished runs" into "the last finished
    runs", and every sentence carrying a number into a fragment — so the judge
    spent its objections on grammar nobody had written, and the real findings sat
    underneath them. A person reading the page sees a value in that gap, so the
    judge is shown one too."""
    out, depth, i, n = [], 0, 0, len(s)
    while i < n:                       # ${ ... } is code, however deeply nested
        if s.startswith("${", i):
            if not depth:
                out.append(VALUE_HERE)
            depth += 1; i += 2; continue
        if depth:
            if s[i] == "{":
                depth += 1
            elif s[i] == "}":
                depth -= 1
            i += 1
            continue
        out.append(s[i]); i += 1
    text = "".join(out)
    # A heading, a paragraph and a card are separate things on the screen, so
    # they are separated here too. Run together by a plain space, a heading and
    # the sentence under it arrive as "The next public release No next release
    # is planned" — and the judge, quite reasonably, objects to a run-on nobody
    # wrote. The middle dot is the separator HQ itself prints between facts.
    text = re.sub(BLOCK_TAG, " · ", text)
    text = re.sub(r"<[^>]*>", " ", text)          # tags, and every attribute in them
    text = re.sub(r"&[a-z]+;|\\[nt]", " ", text)
    text = re.sub(r"\s+", " ", text).strip()
    text = re.sub(r"(?:·\s*)+", "· ", text)       # one boundary, however many tags closed
    return text.strip(" ·").strip()


def is_prose(s):
    """A string worth checking: real words, not a class name, path or id."""
    s = s.strip()
    if len(s) < 12 or " " not in s:
        return False
    if s.startswith(("/", "#", ".", "http")) or "/" in s.split(" ")[0]:
        return False
    # A hand-rolled scanner mis-pairs a quote now and then — an apostrophe in the
    # wrong place swallows the code that follows it — and the result reads as a
    # sentence full of syntax. Nothing a person sees contains an arrow function.
    if re.search(r"=>|\);|\bfunction\b|\bconst\b|\breturn\b|//|\$\{", s):
        return False
    # A literal that starts or ends mid-tag survives rendered_text with its markup
    # attached. It is not writing, and sending it to be judged buys nothing.
    if re.search(r"[<>]|\b(?:class|href|src|style|aria-\w+)\s*=", s):
        return False
    # `gate-src small muted` is a list of CSS classes, not a sentence: no capital,
    # no punctuation, and every word a lowercase identifier.
    if re.fullmatch(r"[a-z][a-z0-9-]*(?: [a-z][a-z0-9-]*)*", s):
        return False
    return len(re.findall(r"[a-z]{3,}", s)) >= 3


def waived(waivers, where, text):
    for w in waivers:
        if w.get("where") in ("", where) and w.get("phrase", "") in text:
            return w.get("why", "waived")
    return ""


def collect(repo=REPO):
    """Every piece of human-facing text, as {text, where, what, near}."""
    found = []
    for pattern, fields, what in DATA_SOURCES:
        for path in sorted(glob.glob(os.path.join(repo, pattern))):
            rel = os.path.relpath(path, repo)
            try:
                doc = json.load(open(path, encoding="utf-8"))
            except (OSError, ValueError):
                continue
            if what == "work card" and doc.get("state") in CLOSED_STATES:
                continue
            # A decision he has already ruled on is a record of a decision, not a
            # question still being put to him. Rewriting the wording he answered
            # would change what the record says he was asked.
            if what == "decision card" and os.path.isfile(
                    os.path.join(repo, "hq", "data", "rulings", os.path.basename(path))):
                continue
            for field in fields:
                for text in walk(doc, field):
                    # A pillar's verdict is a sentence with {unassured} and
                    # {total} filled in before anyone sees it, the same way a
                    # page fills in ${ }. Shown the raw braces, the judge objects
                    # to a missing number that is never missing on the screen.
                    text = DATA_SLOT.sub(VALUE_HERE, text or "")
                    if text.strip():
                        found.append({"text": text.strip(), "where": rel,
                                      "what": f"{what} · {field}", "near": ""})
    for rel in CODE_SOURCES:
        path = os.path.join(repo, rel)
        if not os.path.isfile(path):
            continue
        src = open(path, encoding="utf-8").read()
        lines = src.splitlines()
        for line_no, body in strings_in_js(src):
            text = rendered_text(body)
            if not is_prose(text):
                continue
            found.append({"text": text, "where": rel,
                          "what": f"page text · line {line_no}",
                          "near": "\n".join(lines[max(0, line_no - 2):line_no + 1])})
    # One text can appear on several screens; judge it once.
    seen, unique = set(), []
    for row in found:
        if row["text"] in seen:
            continue
        seen.add(row["text"])
        unique.append(row)
    return unique


# --- the cache ------------------------------------------------------------------

def key_of(text, fingerprint):
    return hashlib.sha256((fingerprint + "\x00" + text).encode()).hexdigest()[:20]


def load_cache():
    try:
        return json.load(open(CACHE, encoding="utf-8"))
    except (OSError, ValueError):
        return {"brief": "", "verdicts": {}}


def save_cache(cache):
    with open(CACHE, "w", encoding="utf-8") as f:
        json.dump(cache, f, indent=1, ensure_ascii=False, sort_keys=True)
        f.write("\n")


# --- the judge ------------------------------------------------------------------

def have_cli():
    return shutil.which(execution.resolve_model(JUDGE_MODEL)['provider']) is not None


def record_cost(usage, phase):
    """Work the company does on its own spends the same allotment Daniel does,
    so it says what it cost. Best-effort: never fail the check over bookkeeping."""
    path = os.path.join(REPO, "hq", "data", "history", "tokens.jsonl")
    if not usage or not os.path.isdir(os.path.dirname(path)):
        return
    try:
        import datetime
        row = {"at": datetime.datetime.now().isoformat(timespec="seconds"),
               "phase": phase, "seat": "writing judge", "item": "check_writing",
               **usage}
        with open(path, "a", encoding="utf-8") as f:
            f.write(json.dumps(row) + "\n")
    except OSError:
        pass


def parse_findings(body):
    """The judge's findings, out of a reply that is JSON on a good day.

    A judge quoting the text back at us will sooner or later put a quote mark or
    a newline somewhere JSON does not allow, and a whole sweep once died on one
    malformed reply. So: try the clean parse, then the braces, and if both fail
    pull the findings out object by object. A batch we genuinely cannot read is
    reported as unread rather than silently passed — see judge()."""
    for attempt in (body, ):
        try:
            got = json.loads(attempt)
            if isinstance(got, dict) and isinstance(got.get("findings"), list):
                return got["findings"]
        except ValueError:
            pass
    m = re.search(r"\{.*\}", body or "", re.S)
    if m:
        try:
            return json.loads(m.group(0)).get("findings", []) or []
        except ValueError:
            pass
    # Object-by-object salvage: one unparseable finding loses that finding, not
    # the other twenty-four in the batch.
    out = []
    for chunk in re.findall(r"\{[^{}]*\}", body or "", re.S):
        try:
            got = json.loads(chunk)
        except ValueError:
            continue
        if isinstance(got, dict) and "n" in got:
            out.append(got)
    if out:
        return out
    raise RuntimeError("the judge did not answer in JSON")


def judge(texts, system, phase="writing-check"):
    """One call for a batch. Returns {index: finding} for what it objected to."""
    if not texts:
        return {}
    numbered = "\n\n".join(f"[{i}] {t}" for i, t in enumerate(texts)) + (
        "\n\n---\nReply with the JSON object and nothing else — no preamble, no "
        "explanation of your approach, no code fence. If none of the texts above is "
        "worth reporting, the whole reply is exactly: {\"findings\": []}")
    envelope = execution.run_session(numbered, system, "", JUDGE_MODEL, REPO,
                                     CALL_TIMEOUT, 1, phase=phase,
                                     item="check_writing", launch_context="writing_hook")
    record_cost(envelope["usage"], phase)
    if envelope["error"]:
        raise RuntimeError("the judge failed: " + envelope["error"][:200])
    body = envelope["text"]
    out = {}
    for f in parse_findings(body):
        try:
            n = int(f["n"])
        except (KeyError, TypeError, ValueError):
            continue
        quote = (f.get("quote") or "").strip()
        # The quote is the discipline. Without one there is nothing to check the
        # judge against, and a finding nobody can verify is just nagging.
        if not (0 <= n < len(texts)) or not quote or quote.lower() not in texts[n].lower():
            continue
        if f.get("verdict") not in ("second-look", "decode"):
            continue
        out[n] = {"verdict": f["verdict"], "quote": quote,
                  "why": (f.get("why") or "").strip(),
                  "instead": (f.get("instead") or "").strip()}
    return out


def judge_or_split(chunk, system, phase):
    """Every text in the chunk with its verdict, or None where it defeated us.

    A reply that will not parse is nearly always a reply that got too long, so a
    failed batch is halved and tried again rather than written off — which both
    rescues the texts either side of the awkward one and isolates the awkward one
    down to a batch of one. Two full passes once left a hundred texts unread
    because a whole batch died on whichever of its twenty-five was unquotable.
    A single text that still fails comes back None: the run says so, exits
    non-zero, and the next run tries only it."""
    try:
        found = judge(chunk, system, phase)
        return [(t, found.get(i) or {"verdict": "ok"}) for i, t in enumerate(chunk)]
    except RuntimeError as e:
        if len(chunk) == 1:
            print(f"  could not read the judge on “{chunk[0][:60]}…”: {e}")
            return [(chunk[0], None)]
    half = len(chunk) // 2
    return (judge_or_split(chunk[:half], system, phase)
            + judge_or_split(chunk[half:], system, phase))


def verdicts_for(texts, rulings=None, refresh=True, phase="writing-check"):
    """Cached verdict per text, judging only what has not been judged before."""
    rulings = rulings or load_rulings()
    fp = brief_fingerprint(rulings)
    cache = load_cache()
    if cache.get("brief") != fp:
        cache = {"brief": fp, "verdicts": {}}     # the standard moved; start again
    store = cache["verdicts"]
    missing = [t for t in texts if key_of(t, fp) not in store]
    unread = 0
    if missing and refresh:
        system = SYSTEM % brief_text(rulings)
        for i in range(0, len(missing), BATCH):
            chunk = missing[i:i + BATCH]
            for text, verdict in judge_or_split(chunk, system, phase):
                if verdict is None:
                    unread += 1
                else:
                    store[key_of(text, fp)] = verdict
            save_cache(cache)      # after every batch, not at the end
    return {t: store.get(key_of(t, fp)) for t in texts}, unread


# --- reporting -------------------------------------------------------------------

def baseline_cache(cache=None):
    """Mark every objection standing today as known, so CI is not red about text
    nobody has touched.

    A failing build has to mean something broke. Forty-two sentences that were
    already on the screens when the judge arrived are a backlog, not a breakage,
    so they are recorded here and filed as work instead. Anything written after
    this date fails the build in the ordinary way, and a baselined line loses its
    grandfathering the moment somebody edits it — the text is the cache key, so a
    reworded sentence is a new one."""
    import datetime
    cache = cache or load_cache()
    today = datetime.date.today().isoformat()
    n = 0
    for v in cache["verdicts"].values():
        if v.get("verdict") in ("decode", "second-look") and not v.get("baselined"):
            v["baselined"] = today
            n += 1
    save_cache(cache)
    return n


def report(rows, unjudged=0, strict=False):
    # `strict` decides what gets PRINTED — CI wants only what is new, HQ's page
    # wants the whole backlog visible. What FAILS is the same either way: text
    # written since the baseline. A red that means "forty-two old sentences are
    # still on the list" is a red about bookkeeping, and those get ignored.
    if strict:
        rows = [r for r in rows if not r.get("baselined")]
    hard = [r for r in rows if r["verdict"] == "decode"]
    soft = [r for r in rows if r["verdict"] == "second-look"]
    new_hard = [r for r in hard if not r.get("baselined")]
    for row in sorted(rows, key=lambda r: (r["verdict"] != "decode", r["where"])):
        mark = "MUST FIX" if row["verdict"] == "decode" else "consider"
        print(f"  {mark}  {row['where']}")
        print(f"            “{row['text'][:160]}”")
        print(f"            “{row['quote']}” — {row['why']}")
        if row.get("instead"):
            print(f"            say: {row['instead']}")
    print()
    if unjudged:
        print(f"{unjudged} piece(s) of text have changed and have not been read yet — "
              f"run `python3 tools/check_writing.py` to judge them.")
        return 1
    if new_hard:
        print(f"{len(new_hard)} phrase(s) Daniel would have to decode, and "
              f"{len([r for r in soft if not r.get('baselined')])} worth a second look.")
        print("Each one is exact to whoever wrote it and empty three feet away.")
        return 1
    known_hard = len(hard) - len(new_hard)
    known_soft = sum(1 for r in soft if r.get("baselined"))
    fresh_soft = len(soft) - known_soft
    print("Nothing new he would have to decode"
          + (f"; {fresh_soft} worth a second look." if fresh_soft else "."))
    if known_hard or known_soft:
        print(f"{known_hard} older phrase(s) he would have to decode and {known_soft} "
              f"worth a second look were already on the screens when this check "
              f"arrived, and are filed as work rather than failing the build.")
    return 0


def rows_for(items, table, waivers, allow):
    rows = []
    for it in items:
        v = table.get(it["text"])
        if not v or v.get("verdict") == "ok":
            continue
        why = waived(waivers, it["where"], it["text"])
        if not why and it.get("near"):
            m = WAIVER.search(it["near"])
            why = m.group(1) if m else ""
        if why:
            allow.append({"where": it["where"], "quote": v.get("quote", ""), "waiver": why})
            continue
        rows.append({**it, **v})   # v carries `baselined` when it has one
    return rows


# --- the modes --------------------------------------------------------------------

def sweep(refresh=True, strict=False):
    rulings = load_rulings()
    items = collect()
    table, _ = verdicts_for([i["text"] for i in items], rulings, refresh=refresh)
    unjudged = sum(1 for i in items if table.get(i["text"]) is None)
    allow = []
    rows = rows_for(items, table, rulings.get("waivers", []), allow)
    for a in sorted(allow, key=lambda r: r["where"]):
        print(f"  allowed  {a['where']} — “{a['quote']}” — {a['waiver']}")
    if allow:
        print()
    return report(rows, unjudged, strict)


def check_subject(path_or_text):
    """One commit subject, judged before the commit exists.

    This is the only place that could have stopped the sentence that started all
    of this. Once a commit is written, the only fix is rewriting published
    history, which the CEO has ruled out."""
    if os.path.isfile(path_or_text):
        raw = open(path_or_text, encoding="utf-8").read()
    else:
        raw = path_or_text
    subject = ""
    for line in raw.splitlines():
        if line.strip().startswith("#"):
            continue
        subject = line.strip()
        break
    if not subject or subject.lower().startswith(("merge ", "revert ", "fixup!", "squash!")):
        return 0
    if not have_cli():
        print("plain-language check skipped: the claude CLI is not on PATH.")
        return 0
    try:
        table, _ = verdicts_for([subject], phase="writing-check-subject")
    except RuntimeError as e:
        print(f"plain-language check skipped: {e}")
        return 0
    v = table.get(subject) or {"verdict": "ok"}
    if v["verdict"] != "decode":
        if v["verdict"] == "second-look":
            print(f"  worth a second look: “{v['quote']}” — {v['why']}")
            if v.get("instead"):
                print(f"  say: {v['instead']}")
        return 0
    print()
    print("This commit subject is one Daniel would have to decode.")
    print(f"  you wrote : {subject}")
    print(f"  the problem: “{v['quote']}” — {v['why']}")
    if v.get("instead"):
        print(f"  say       : {v['instead']}")
    print()
    print("Commit subjects are rendered on HQ's \"What we shipped this week\", so this")
    print("is a page he reads, not a developer-only note. Reword it and commit again.")
    print("If the wording is genuinely right, commit with --no-verify.")
    return 1


def self_test():
    """Replay every ruling and prove the judge still makes the same call.

    A model judge cannot be made deterministic, but it can be held to every line
    ever drawn — which is what catches it drifting, here or under a new model."""
    rulings = load_rulings()
    cases = []
    for shape in rulings["shapes"]:
        for r in shape["rulings"]:
            cases.append((r["text"], r["verdict"], shape["id"]))
    for r in rulings["ruled_fine"]:
        cases.append((r["text"], "ok", "ruled fine"))
    table, _ = verdicts_for([c[0] for c in cases], rulings, phase="writing-check-selftest")
    ok = True
    for text, want, where in cases:
        got = (table.get(text) or {"verdict": "ok"})["verdict"]
        # "decode" and "second-look" are both objections; the tiers are a judgement
        # of severity and holding the judge to the exact tier would make this brittle.
        agree = (got == want) or (want != "ok" and got != "ok")
        label = "agrees " if agree else "DIFFERS"
        print(f"  {label}  [{where}] wanted {want:12} got {got:12} “{text[:48]}…”")
        ok = ok and agree
    return ok


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--list", action="store_true", help="print the rulings and stop")
    ap.add_argument("--self-test", action="store_true",
                    help="replay every past ruling and prove the judge still agrees")
    ap.add_argument("--verify", action="store_true",
                    help="offline: has everything been judged, and did it pass")
    ap.add_argument("--subject", metavar="FILE_OR_TEXT",
                    help="judge one commit subject (used by the commit-msg hook)")
    ap.add_argument("--baseline", action="store_true",
                    help="record today's objections as known, so CI fails only on new ones")
    args = ap.parse_args(argv)

    if args.list:
        rulings = load_rulings()
        for shape in rulings["shapes"]:
            print(f"\n{shape['shape']}")
            print(f"  {shape['why_it_fails']}")
            for r in shape["rulings"]:
                print(f"    {r['verdict']:12} “{r['text'][:64]}”")
                print(f"    {'':12} say: {r['instead'][:64]}")
        print("\nRuled fine — the line sits above these:")
        for r in rulings["ruled_fine"]:
            print(f"    {'ok':12} “{r['text'][:64]}”")
        return 0

    if args.baseline:
        n = baseline_cache()
        print(f"{n} standing objection(s) recorded as known. CI now fails only on "
              f"text written after today; editing any of them puts it back in scope.")
        return 0

    if args.subject:
        return check_subject(args.subject)

    if args.self_test:
        if not have_cli():
            print("SELF-TEST SKIPPED: the claude CLI is not on PATH.")
            return 0
        print("Replaying every call Daniel has made, against the judge as it stands:")
        good = self_test()
        print("SELF-TEST PASSED" if good else "SELF-TEST FAILED")
        return 0 if good else 1

    if args.verify:
        print("Every surface he reads, against the verdicts already recorded "
              "(offline — no model is called).")
        return sweep(refresh=False, strict=True)

    print("Every surface he reads, judged against docs/WRITING.md and "
          "docs/writing_rulings.json.")
    if not have_cli():
        print("The claude CLI is not on PATH, so nothing new can be judged.")
        return sweep(refresh=False)
    return sweep(refresh=True)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
