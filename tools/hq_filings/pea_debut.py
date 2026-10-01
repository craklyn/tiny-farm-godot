#!/usr/bin/env python3
"""File the pea-debut cards in HQ (Daniel's ask, 2026-10-01).

End state once every card is closed: pea seeds are on the shop shelf, she can buy,
plant, grow, harvest and sell peas, and that build is on the tablet and the public
page.

HQ has no dependency field, but the drain works cards of equal priority in the
order they were filed, so this files them in dependency order and each card's
first action checks its prerequisites by title before starting.

Run on the desktop where HQ is running:

    python3 tools/hq_filings/pea_debut.py --dry-run   # print what would be filed
    python3 tools/hq_filings/pea_debut.py             # file them

A card whose title is already on HQ is skipped, so a second run files nothing twice.
"""
import argparse
import json
import sys
import time
import urllib.request

PREFIX = "Peas: "

T_RULE = PREFIX + "decide when pea seeds go on the shelf and what they cost"
T_ECON = PREFIX + "check the pea's prices against wheat and tomato"
T_LOOK = PREFIX + "set the look of the pea seed packet"
T_ICON = PREFIX + "draw the pea seed packet for the shop"
T_UX = PREFIX + "make room for a third seed in the shop, seed box and HUD"
T_BUILD = PREFIX + "put pea seeds on the shop shelf"
T_QA = PREFIX + "test buying, planting and harvesting peas in the real game"
T_SHIP = PREFIX + "send the pea build to the tablet and the public page"


def waits_for(*titles):
    names = "; ".join(f"“{t}”" for t in titles)
    return (f"First check these cards are closed with their work on origin/main: {names}. "
            "If any is still open, stop and say on this card which one you are waiting for. ")


CARDS = [
    {
        "title": T_RULE, "owner": "milo", "level": "story", "tier": 1,
        "ask": (
            "Daniel asked 2026-10-01 to debut the pea: buy seeds in the shop, plant, harvest. "
            "This lifts Q-55's 'shop does not sell pea seeds'. Pea already exists in "
            "crops/crop_defs.gd (3 days, sells 20, seed 8, all [Playtest]; unlock wheat x1, "
            "same as tomato) but is absent from CropDefs.ORDER. Decide the unlock rule and "
            "the numbers, and where it sits in the shelf order. Record as a P-# in "
            "docs/DECISION_LOG.md, in docs/design/02-farming-system.md, and annotate Q-55 in "
            "docs/DESIGNER_QUEUE.md."),
        "first_action": (
            "Read Q-55/Q-56 in docs/DESIGNER_QUEUE.md, design/02 and design/12. Keep the "
            "pea a crop that is a fair choice, never the obvious one. If a choice needs "
            "Daniel's taste, prep a decision card in hq/data/decisions/ with a "
            "recommendation instead of deciding it. Do not edit crop_defs.gd; Anna applies "
            "the numbers."),
    },
    {
        "title": T_ECON, "owner": "marcus", "level": "task", "tier": 1,
        "ask": (
            "With the pea's numbers from Milo's ruling, check gold per tile per day against "
            "wheat (3d, 15, free starter seed) and tomato (5d, 30, seed 10): the pea must not "
            "make tomato or wheat pointless, must be affordable when it unlocks, and must "
            "not break the S-18 carry cap of 100. Write the table and verdict into "
            "docs/design/02-farming-system.md. If the numbers should change, say so to Milo "
            "in the same patch's DECISION_LOG entry rather than overriding him."),
        "first_action": waits_for(T_RULE) + (
            "Use the robot/benchmark tools only if a table needs measured days; a worked "
            "calculation is enough."),
    },
    {
        "title": T_LOOK, "owner": "ingrid", "level": "task", "tier": 1,
        "ask": (
            "Write the art brief for a pea seed packet: a 16x16 icon in "
            "assets/sprites/generated/shop_icons.png, same family as the wheat (col 0) and "
            "tomato (col 1) packets, readable at tablet size, using the pod green #a3c263 "
            "from systems/crop_presentation.gd. While there, check pea.png's four growth "
            "stages and its ripe light sit beside wheat and tomato on the farm "
            "(tools/capture_ripe_glow.gd). Put the brief and verdict in "
            "docs/design/09-art-direction.md."),
        "first_action": (
            "Read docs/design/09-art-direction.md and docs/design/spritesmith.md first. Name "
            "in the brief whether a palette remap of the tomato packet would meet it, so Yuki "
            "can try that before any generation call."),
    },
    {
        "title": T_ICON, "owner": "yuki", "level": "task", "tier": 1,
        "ask": (
            "Draw the pea seed packet to Ingrid's brief as a new column 6 of "
            "assets/sprites/generated/shop_icons.png (today 96x16: wheat, tomato, scarecrow, "
            "coin, droplet, basket). Then point the pea's icon_col in crops/crop_defs.gd at "
            "6, remove the 'trap' comment there, and update the sheet comments in "
            "ui/menus.gd and ui/hud.gd. Provenance in CREDITS.md."),
        "first_action": waits_for(T_LOOK) + (
            "Try tools/spritesmith.py (palette remap of the tomato packet) before any Retro "
            "Diffusion call; if you do generate, archive raw outputs under assets/raw/ per "
            "its README. Re-import with godot --headless --import."),
    },
    {
        "title": T_UX, "owner": "sam", "level": "task", "tier": 1,
        "ask": (
            "A third seed is coming to the shelf. Check every place a seed is chosen fits it "
            "at tablet size: the shop's seed cards (ui/menus.gd), the seed box's Take list, "
            "the HUD seed pill and crop counts (ui/hud.gd), and the locked look before the "
            "pea unlocks. Keyboard: main.gd only maps 1=wheat, 2=tomato; specify 3=pea. Say "
            "whether Milo's unlock rule needs a teaching hint (systems/teaching_focus.gd). "
            "Write the spec in docs/design/11-ux-ui.md; fix layout only if it breaks."),
        "first_action": waits_for(T_RULE) + (
            "Capture the shop with three seed rows before deciding anything needs to "
            "change; most of these lists already iterate CropDefs.ORDER."),
    },
    {
        "title": T_BUILD, "owner": "anna", "level": "story", "tier": 1,
        "ask": (
            "Debut the pea: add it to CropDefs.ORDER and apply Milo's unlock rule and "
            "numbers. Add pea to the starting dicts in systems/game_state.gd (~line 216), "
            "main.gd key 3 per Sam's spec, and check every crop list (world/farm.gd, seed "
            "box, shipping bin, storage). Old saves and replay logs without pea keys must "
            "still load and replay. Unit tests in tests/test_runner.gd: buy_seed pea, plant, "
            "water, grow, harvest, sell. Remove the 'pea absent from shelf' comments in "
            "crop_defs.gd."),
        "first_action": waits_for(T_RULE, T_ECON, T_ICON, T_UX) + (
            "Run both suites and the robot session; replay format must not change "
            "(CLAUDE.md, load-bearing rules)."),
    },
    {
        "title": T_QA, "owner": "grace", "level": "task", "tier": 1,
        "ask": (
            "Prove the pea end to end in the real main scene: an integration test in "
            "tools/test_runner.gd that unlocks the pea, buys seeds in the shop with "
            "simulated taps, plants, waters, sleeps until ripe, harvests and ships, and "
            "checks gold. Load a save made before the pea existed and check it plays on. "
            "Have the robot session plant at least one pea so its replay check covers it."),
        "first_action": waits_for(T_BUILD) + (
            "Report anything that only a person on the tablet can judge on this card for "
            "Ravi's deploy."),
    },
    {
        "title": T_SHIP, "owner": "ravi", "level": "task", "tier": 2,
        "ask": (
            "Ship the pea. Install the build on the tablet per docs/DEPLOY.md section 2, "
            "then publish the public release per section 3 (its 'Before any release' "
            "checklist; a pushed v* tag, never a push to main). The release note names the "
            "pea in one plain sentence. Done means Daniel can buy, plant and harvest peas "
            "in the public build."),
        "first_action": waits_for(T_QA) + (
            "Confirm CI is green on the commit being tagged. Remember installing overwrites "
            "the tablet's session, so pull it first (DEPLOY.md, Pulling a play session)."),
    },
]


def call(url, path, payload=None):
    req = urllib.request.Request(url + path, method="POST" if payload is not None else "GET",
                                 data=json.dumps(payload).encode() if payload is not None else None,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--url", default="http://localhost:8642")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    for card in CARDS:
        for field in ("ask", "first_action"):
            assert len(card[field]) <= 600, f"{card['title']}: {field} is {len(card[field])} chars"
        assert len(card["title"]) <= 160, card["title"]

    if args.dry_run:
        for n, card in enumerate(CARDS, 1):
            print(f"{n}. [{card['owner']}, tier {card['tier']}] {card['title']}")
        return 0

    have = {i.get("title") for i in call(args.url, "/api/work").get("items", [])}
    for card in CARDS:
        if card["title"] in have:
            print(f"skip (already on HQ): {card['title']}")
            continue
        got = call(args.url, "/api/work/new", card)
        if got.get("error") or not got.get("id"):
            print(f"FAILED: {card['title']}: {got}", file=sys.stderr)
            return 1
        print(f"{got['id']}  [{got.get('owner')}, {got.get('state')}]  {card['title']}")
        time.sleep(1.1)  # keep created_ts strictly in filing order
    return 0


if __name__ == "__main__":
    sys.exit(main())
