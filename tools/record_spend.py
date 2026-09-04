#!/usr/bin/env python3
"""Append one paid-run entry to hq/data/spend.json (spend-ledger project, step 2).

Every paid pixel-art API call has so far been written down in CREDITS.md prose
after the fact, which is why the studio's spend record does not reconcile — see
hq/data/projects/spend-ledger.json. This is the gateway meant to replace that:
the art pipeline (and anything else that spends money) calls it the moment a
paid run returns, so the ledger is a log of facts, not a memory of them.

Appends to the "entries" list; any other top-level key already in the file
(currency, notes, a backfill's own additions) round-trips untouched. If the
file doesn't exist yet, a minimal {"currency": "USD", "entries": []} is created
— this script owns the list, nothing else about the file's shape.

    python3 tools/record_spend.py --purpose "T-27 sheet, box 5" --dollars 0.058 \\
        --credits 5.8 --balance-after 1.858 --work-item T-27
"""
import argparse
import datetime
import json
import re
import os
import sys

LEDGER = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "hq", "data", "spend.json")


def die(msg):
    sys.exit(f"record_spend: {msg}")


def clean(n):
    """Whole-number floats print as ints, so the ledger doesn't fill with .0s."""
    return None if n is None else (int(n) if float(n).is_integer() else n)


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--purpose", required=True)
    p.add_argument("--dollars", required=True, type=float)
    p.add_argument("--credits", type=float, default=None)
    p.add_argument("--balance-after", type=float, default=None)
    p.add_argument("--work-item", default=None)
    p.add_argument("--date", default=None, help="YYYY-MM-DD, default today")
    args = p.parse_args()

    if args.dollars < 0:
        die(f"--dollars must not be negative, got {args.dollars}")
    if args.date is None:
        date = datetime.date.today().isoformat()
    else:
        try:
            date = datetime.datetime.strptime(args.date, "%Y-%m-%d").date().isoformat()
        except ValueError:
            die(f"--date must be YYYY-MM-DD, got {args.date!r}")

    # Field names and order match the backfilled entries (the finance seat owns
    # the shape); the id is the same date-slug form the backfill uses.
    slug = re.sub(r"[^a-z0-9]+", "-", args.purpose.lower()).strip("-")[:40]
    entry = {
        "id": f"{date}-{slug}",
        "date": date,
        "vendor": "Retro Diffusion",
        "kind": "generation",
        "purpose": args.purpose,
        "work_item": args.work_item,
        "dollars": clean(args.dollars),
        "credits": clean(args.credits),
        "balance_after": clean(args.balance_after),
        "reconciled": args.balance_after is not None,
        "recorded_by": "record_spend",
    }

    if os.path.isfile(LEDGER):
        with open(LEDGER, encoding="utf-8") as f:
            ledger = json.load(f)
    else:
        ledger = {"currency": "USD", "entries": []}

    ledger.setdefault("entries", []).append(entry)

    tmp = LEDGER + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(ledger, f, ensure_ascii=False, indent=2)
        f.write("\n")
    os.replace(tmp, LEDGER)

    print(f"recorded ${entry['dollars']} — {args.purpose} ({date})")


if __name__ == "__main__":
    main()
