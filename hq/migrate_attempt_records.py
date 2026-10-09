#!/usr/bin/env python3
"""Backfill stable causes and token costs on legacy work attempts.

This explicit, idempotent command routes every card mutation through HQ's
action dispatcher. It prints the card identifiers changed by this run.
"""
import json

import action_dispatch
import work


def main():
    migrated = action_dispatch.migrate_attempt_records(work)
    print(json.dumps({"migrated": migrated, "count": len(migrated)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
