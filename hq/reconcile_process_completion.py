#!/usr/bin/env python3
"""Preview or apply the reviewed twelve-card process reconciliation."""
import argparse
import json
from pathlib import Path

import work
import roots


class FileHost:
    def __init__(self, data):
        self.DATA = str(data)

    @staticmethod
    def load_json(path):
        return json.loads(Path(path).read_text())

    def load_org(self):
        return self.load_json(Path(self.DATA) / "org.json")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true",
                        help="write the reviewed transitions; without this flag the command is read-only")
    parser.add_argument("--data-root", type=Path,
                        default=Path(roots.ROOTS["data"]),
                        help=argparse.SUPPRESS)
    parser.add_argument("--manifest", type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    work.bind(FileHost(args.data_root), sanitize=False)
    report = work.reconcile_process_completion(manifest=args.manifest, apply=args.apply)
    print(json.dumps(report, indent=2))
    return 0 if report["applicable"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
