"""Validate a private preview store before any HQ writer is bound to it."""
import os
from pathlib import Path

MARKER = ".hq-social-preview"
PURPOSE = "Tiny Farm isolated social preview v1\n"
STORE_MARKER = "Isolated social preview; not the live HQ store.\n"


def prepare_data(raw, *, persistent=False, protected=(), temporary_root=Path("/tmp")):
    requested = Path(raw)
    if not requested.is_absolute() or requested.is_symlink():
        raise ValueError("Preview data must be an absolute directory without a symlink.")
    data = requested.resolve()
    roots = [Path(__file__).resolve().parent.parent,
             Path.home() / "tiny-farm-hq-data", *map(Path, protected)]
    roots += [Path(os.environ[name]) for name in
              ("HQ_DATA_ROOT", "HQ_MAIN_ROOT", "HQ_USER_WORKSPACE_ROOT") if os.environ.get(name)]
    for root in roots:
        root = root.resolve()
        if data == root or data.is_relative_to(root) or root.is_relative_to(data):
            raise ValueError("Preview data cannot overlap a live store, code checkout, media root or their ancestors.")
    if not persistent and (not data.is_relative_to(temporary_root.resolve()) or data == temporary_root.resolve()):
        raise ValueError("Persistent preview data requires the explicit --persistent-preview option.")
    if data.exists() and not data.is_dir():
        raise ValueError("Preview data must be a directory.")
    marker = data / MARKER
    if data.exists() and any(data.iterdir()):
        if marker.is_symlink() or not marker.is_file() or marker.read_text() != PURPOSE:
            raise ValueError("A nonempty preview directory must already carry the private social-preview marker.")
        common = data / ".hq-store"
        if common.is_symlink() or not common.is_file() or common.read_text() != STORE_MARKER:
            raise ValueError("This is not an isolated social-preview store.")
    if data.exists():
        for directory, folders, files in os.walk(data, followlinks=False):
            for name in folders + files:
                if (Path(directory) / name).is_symlink():
                    raise ValueError("Preview records cannot contain symlinks, including nested files or writable folders.")
    data.mkdir(parents=True, exist_ok=True, mode=0o700)
    data.chmod(0o700)
    if not marker.exists():
        with marker.open("x") as f:
            f.write(PURPOSE)
        with (data / ".hq-store").open("x") as f:
            f.write(STORE_MARKER)
    return data
