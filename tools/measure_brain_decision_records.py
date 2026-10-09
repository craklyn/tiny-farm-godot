#!/usr/bin/env python3
"""Calculate a conservative upper bound for no-Action decision records."""

import hashlib
import json
import math


TICKS_PER_SECOND = 10
WINDOW_START_TICK = 6_000

# name, actor identifier, seconds changing comparable state, ticks per change
ROWS = [
    ("Hen", "chicken", 300, 8),
    ("Crow", "crow", 60, 1),
    ("Ant scout", "ant_scout", 60, 16),
    ("Ant forager", "ant_forager", 60, 20),
    ("Rabbit", "rabbit", 60, 5),
    ("Kangaroo", "kangaroo", 60, 4),
    ("Songbird", "songbird", 60, 1),
    ("Mole", "mole", 60, 8),
    ("Worm", "worm", 60, 27),
    ("Robot: orders", "bot_orders", 300, 5),
    ("Robot: idle", "bot_idle", 0, 5),
    ("Robot: follow", "bot_follow", 300, 5),
    ("Robot: circle", "bot_circle", 300, 5),
    ("Robot: shoo", "bot_shoo", 300, 5),
    ("Robot: learn", "bot_learn", 300, 5),
    ("Cow", "cow", 300, 8),
    ("Neighbour", "neighbour", 0, 6),
    ("Sprinkler", "sprinkler", 0, 1),
]


def encoded_record(actor: str, tick: int) -> bytes:
    # A fingerprint is always a 64-character lowercase SHA-256 hexadecimal string.
    entry = {
        "kind": "brain_decision",
        "actor": actor,
        "brain": True,
        "brain_fingerprint": "0" * 64,
        "tick": tick,
    }
    return (json.dumps(entry, separators=(",", ":")) + "\n").encode()


def calculate() -> list[tuple[str, int, int]]:
    result = []
    for name, actor, active_seconds, ticks_per_change in ROWS:
        changes = math.ceil(active_seconds * TICKS_PER_SECOND / ticks_per_change)
        size = sum(
            len(encoded_record(actor, WINDOW_START_TICK + i * ticks_per_change))
            for i in range(changes)
        )
        result.append((name, changes, size))
    return result


def main() -> None:
    print("UPPER-BOUND MODEL; this does not execute brain steps")
    result = calculate()
    print("actor\tdecisions\tbytes")
    for name, decisions, size in result:
        print(f"{name}\t{decisions}\t{size}")
    total_decisions = sum(row[1] for row in result)
    total_bytes = sum(row[2] for row in result)
    canonical = json.dumps(result, separators=(",", ":")).encode()
    print(f"TOTAL\t{total_decisions}\t{total_bytes}")
    print(f"SHA256\t{hashlib.sha256(canonical).hexdigest()}")


if __name__ == "__main__":
    main()
