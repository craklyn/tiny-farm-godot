#!/usr/bin/env python3
"""Catch house vocabulary before it reaches the one person who cannot ask it what it means.

Daniel, 2026-09-04, reading a work card titled "Re-run the suites so each stamps
the commit it proved":

    "What are the suites? I think it's test suites, but I don't have enough
    context on this page to know. 'stamps' and 'proves' are terms of art, not
    literal? ... We need a way to eradicate all of this hard to handle text.
    It's only causing friction, and the friction is so severe that it's getting
    in way of the process."

The instruction is about mechanism. `docs/WRITING.md` has said "no house
vocabulary on human surfaces" since 2026-09-03 and the rule kept being broken,
because it depended on somebody noticing — and the person who notices is the one
the rule exists to protect. So the rule gets a checker, the way the engine's
one-gateway rule got one: a rule nobody has watched fail is only a claim that the
rule holds.

What it reads: the text fields that end up on screen — work-card titles, goal
statements, decision-card questions and options, pillar names and taglines — plus
the string literals in HQ's front-end code. Deliberately NOT: work-card briefs,
persona prompts, code comments and design docs, which are written for agents,
for machines, or for a teammate looking something up, and where a precise
internal name is the right word.

    python3 tools/check_writing.py              # every human-facing surface
    python3 tools/check_writing.py --list       # the glossary, as a table
    python3 tools/check_writing.py --self-test  # plant each shape and prove it is caught

A line that genuinely needs the word says so with `plain-ok: <reason>` on it (in
code) or through a waiver in `docs/glossary.json` (in data), and the waiver is
printed rather than hidden — an excuse nobody can see is indistinguishable from a
rule nobody applies.
"""
import argparse
import json
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GLOSSARY = os.path.join(REPO, "docs", "glossary.json")
WAIVER = re.compile(r"plain-ok:\s*(\S.*)$")

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


def load_glossary(path=GLOSSARY):
    doc = json.load(open(path, encoding="utf-8"))
    terms = []
    for t in doc.get("terms", []):
        terms.append({**t, "rx": re.compile(r"\b(?:%s)" % t["term"], re.I)})
    return terms, doc.get("waivers", [])


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
    file. Only what can reach the screen is checked."""
    out = []
    i, line, n = 0, 1, len(text)
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
        if c in "'\"`":
            start, j = i + 1, i + 1
            while j < n and text[j] != c:
                if text[j] == "\\":
                    j += 1
                j += 1
            body = text[start:j]
            out.append((line, body))
            line += body.count("\n")
            i = j + 1
            continue
        i += 1
    return out


def is_prose(s):
    """A string worth checking: real words, not a class name, path or id."""
    s = s.strip()
    if len(s) < 12 or " " not in s:
        return False
    if s.startswith(("/", "#", ".", "http")) or "/" in s.split(" ")[0]:
        return False
    return len(re.findall(r"[a-z]{3,}", s)) >= 3


def waived(waivers, where, text):
    for w in waivers:
        if w.get("where") in ("", where) and w.get("phrase", "") in text:
            return w.get("why", "waived")
    return ""


def scan(repo=REPO, terms=None, waivers=None):
    import glob
    if terms is None:
        terms, waivers = load_glossary()
    hits, excused = [], []

    def check(text, where, what, extra=""):
        for t in terms:
            m = t["rx"].search(text or "")
            if not m:
                continue
            why = waived(waivers, where, text) or (
                WAIVER.search(extra).group(1) if WAIVER.search(extra) else "")
            row = {"where": where, "what": what, "term": m.group(0), "text": text.strip()[:160],
                   "instead": t["instead"], "means": t["means"], "hard": t.get("hard", True)}
            (excused if why else hits).append(dict(row, waiver=why) if why else row)

    for pattern, fields, what in (DATA_SOURCES if terms else []):
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
                    check(text, rel, f"{what} · {field}")

    for rel in CODE_SOURCES:
        path = os.path.join(repo, rel)
        if not os.path.isfile(path):
            continue
        src = open(path, encoding="utf-8").read()
        lines = src.splitlines()
        for line_no, body in strings_in_js(src):
            if not is_prose(body):
                continue
            near = "\n".join(lines[max(0, line_no - 2):line_no + 1])
            check(body, rel, f"page text · line {line_no}", near)
    return hits, excused


def report(hits, excused):
    for row in sorted(excused, key=lambda r: r["where"]):
        print(f"  allowed  {row['where']} — “{row['term']}” — {row['waiver']}")
    if excused:
        print()
    for row in sorted(hits, key=lambda r: (not r["hard"], r["where"])):
        mark = "MUST FIX" if row["hard"] else "consider"
        print(f"  {mark}  {row['where']}")
        print(f"            “{row['text']}”")
        print(f"            “{row['term']}” means {row['means']} — say: {row['instead']}")
    hard = [r for r in hits if r["hard"]]
    print()
    if hard:
        print(f"{len(hard)} phrase(s) Daniel would have to decode, and "
              f"{len(hits) - len(hard)} worth a second look.")
        print("Each one is a word that is exact to whoever wrote it and empty three feet away.")
    else:
        print(f"No house vocabulary on any surface he reads"
              + (f"; {len(hits)} worth a second look." if hits else "."))
    return 1 if hard else 0


def self_test():
    """Plant each shape of the failure and prove the check sees it."""
    terms, waivers = load_glossary()
    planted = [
        ("Re-run the suites so each stamps the commit it proved", 3),
        ("The attestation lapses when the invariant changes", 2),
        ("Check the provenance and the release cadence for parity", 3),
    ]
    ok = True
    for text, want in planted:
        found = {t["rx"].search(text).group(0).lower()
                 for t in terms if t["rx"].search(text)}
        if len(found) >= want:
            print(f"  caught  {len(found)} in “{text[:52]}…”")
        else:
            print(f"  MISSED  only {len(found)} of {want} in “{text}” — {found}")
            ok = False
    clean = "Run the four test suites again so each result records which version it tested"
    bad = [t["term"] for t in terms if t.get("hard", True) and t["rx"].search(clean)]
    if bad:
        print(f"  MISSED  the plain rewrite is flagged by {bad} — the rule would block good text")
        ok = False
    else:
        print("  caught  the plain rewrite passes, so the rule is not just banning words")
    return ok


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--list", action="store_true", help="print the glossary and stop")
    ap.add_argument("--self-test", action="store_true", help="prove the check catches each shape")
    args = ap.parse_args(argv)

    terms, waivers = load_glossary()
    if args.list:
        print(f"{'say this instead':52}  what the banned word meant")
        for t in terms:
            flag = "" if t.get("hard", True) else "  (soft)"
            print(f"{t['instead'][:52]:52}  {t['means']}{flag}")
        return 0
    if args.self_test:
        print("Planting phrases he has actually had to decode:")
        good = self_test()
        print("SELF-TEST PASSED" if good else "SELF-TEST FAILED")
        return 0 if good else 1

    print("Every word on a surface Daniel reads, checked against docs/glossary.json.")
    hits, excused = scan(REPO, terms, waivers)
    return report(hits, excused)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
