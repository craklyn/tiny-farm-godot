#!/usr/bin/env python3
"""A late studio-owned goal informs Daniel without asking him to act."""
from pathlib import Path
import sys
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import server  # noqa: E402


def main():
    with (
        patch.object(server, "eval_measure", return_value={"value": False}),
        patch.object(server, "_escalation", return_value={"reason": "age", "days": 22}),
    ):
        goal = server.eval_goal({
            "id": "late-release", "statement": "The store page matches the build",
            "owner": "ravi", "measure": {}, "compare": {"direction": "truthy"},
            "path_to_green": {"narrative": "Ravi is publishing the corrected text."},
        })

    assert goal["escalation"] == {"reason": "age", "days": 22}
    assert goal["ours"] is True
    assert goal["needs_you"] is False
    print("A late goal stays visible while its next action stays with the studio.")


if __name__ == "__main__":
    main()
