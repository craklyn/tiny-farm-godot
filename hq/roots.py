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
    if marker and not (path / marker).exists():
        raise ValueError(f"{name} is missing {marker}; refusing an empty HQ store")
    return str(path)


def resolve():
    if os.environ.get("HQ_REQUIRE_EXPLICIT_ROOTS") == "1":
        missing = [name for name in _NAMES if not os.environ.get(name)]
        if missing:
            raise ValueError("HQ activation requires explicit roots: " + ", ".join(missing))
        if os.environ.get("HQ_TEST_SCRATCH"):
            raise ValueError("HQ_TEST_SCRATCH cannot be used with explicit activation roots")
    data = _configured_path("HQ_DATA_ROOT", CODE_ROOT / "data", marker="org.json")
    user = _configured_path("HQ_USER_WORKSPACE_ROOT", DEFAULT_REPO, marker=".git")
    main = _configured_path("HQ_MAIN_ROOT", DEFAULT_REPO, marker=".git")
    return {"code": str(CODE_ROOT), "data": data, "user_workspace": user,
            "main": main}


ROOTS = resolve()
