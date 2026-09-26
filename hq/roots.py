"""The four filesystem roles of a running HQ process.

The checked-in implementation stays beside this file.  All mutable HQ records
come from one data directory, while Git facts and worker bases come from the
authoritative local-main repository.  Interactive edits of unfinished assets
may target a different, preserved user workspace.

Without overrides these paths are exactly the historical in-repository paths.
For a relocated service set all three HQ_*_ROOT variables and
HQ_REQUIRE_EXPLICIT_ROOTS=1.  Requiring an existing, marked data directory
prevents a typo from silently starting a second empty studio.
"""

import os
from pathlib import Path


CODE_ROOT = Path(__file__).resolve().parent
DEFAULT_REPO = CODE_ROOT.parent
_NAMES = ("HQ_DATA_ROOT", "HQ_USER_WORKSPACE_ROOT", "HQ_MAIN_ROOT")

# Q-125 (a) splits hq/data in two; docs/hq/HQ_DATA_MIGRATION.md has the table
# and the reason for every entry.
#
# Checked in on main, one copy, read beside the code: configuration and the
# curated design material sessions author and commit. HQ never writes these.
REPO_OWNED = (
    "org.json", "seats.json", "pillars.json", "platforms.json", "surface.json",
    "entities.json", "releases.json", "work_policy.json", "spend.json",
    "completion_reconciliation.json", "process_completion_reconciliation.json",
    "card_state_migration.json",
    "decisions", "projects", "looks",
)
# Live records: HQ writes them while it runs, so they live only in the data
# root. Main does not track them (.gitignore), and hq/tests/test_live_records.py
# fails the build if a commit adds one back.
LIVE_RECORDS = (
    "work", "rulings", "goals", "staff", "sprite_edits", "anim_asks", "anim_runs",
    "maps", "release_plan.json", "attestations.json",
)
# Tracked as the seed for a new store and for tools that run without a store
# (the pre-commit writing check, CI, a fresh clone); the running HQ reads and
# writes only the store's copy. Its one live field is the automatic-work brake,
# which is changed with HQ's Pause control, never by committing this file.
SEEDED = ("execution_policy.json",)
# The file that marks a folder as HQ's own store (written by store.init).
STORE_MARKER = ".hq-store"
# Runtime output HQ writes and main already ignored before Q-125.
RUNTIME = (
    "runs", "history", "patches", "outbox", "probes", "captures", "loop_previews",
    "sprite_backups", "ci_history.json",
)


def _configured_path(name, default, *, marker=None):
    raw = os.environ.get(name)
    if not raw:
        return str(default)
    path = Path(raw)
    if not path.is_absolute():
        raise ValueError(f"{name} must be an absolute path")
    path = path.resolve(strict=True)
    if not path.is_dir():
        raise ValueError(f"{name} must name an existing directory")
    markers = (marker,) if isinstance(marker, str) else tuple(marker or ())
    if markers and not any((path / m).exists() for m in markers):
        raise ValueError(f"{name} is missing {' or '.join(markers)}; refusing an empty HQ store")
    return str(path)


def resolve():
    if os.environ.get("HQ_REQUIRE_EXPLICIT_ROOTS") == "1":
        missing = [name for name in _NAMES if not os.environ.get(name)]
        if missing:
            raise ValueError("HQ activation requires explicit roots: " + ", ".join(missing))
        if os.environ.get("HQ_TEST_SCRATCH"):
            raise ValueError("HQ_TEST_SCRATCH cannot be used with explicit activation roots")
    # A data root that still holds its configuration has org.json; a store
    # made by hq/migrate_store.py has STORE_MARKER instead (Q-125 a).
    data = _configured_path("HQ_DATA_ROOT", CODE_ROOT / "data", marker=("org.json", STORE_MARKER))
    user = _configured_path("HQ_USER_WORKSPACE_ROOT", DEFAULT_REPO, marker=".git")
    main = _configured_path("HQ_MAIN_ROOT", DEFAULT_REPO, marker=".git")
    return {"code": str(CODE_ROOT), "data": data, "user_workspace": user,
            "main": main}


ROOTS = resolve()
