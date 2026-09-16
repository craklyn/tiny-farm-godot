#!/usr/bin/env python3
"""The verdict on the door transition (design/15 §8a, w2b7e51c9d0af).

Reads what tools/measure_door_transition.tscn captured — tools/door_transition/samples.json
and one PNG per frame under tools/door_transition/<scenario>/ — and asks two questions of
every trip through a door:

  (a) Did a fixed landmark on the farm move across the screen without a jump? Its screen
      position is sampled every frame; the step between consecutive frames is compared
      with its neighbours. A smooth zoom changes the step gradually; a cut makes one step
      many times its neighbours.

  (b) Did the picture change without a spike? Consecutive frames are diffed (mean absolute
      difference over all pixels). A smooth zoom gives a small, steadily changing
      difference; a jump or a content pop gives one frame far above the rest.

  (c) Was the swap frame drawn from the picture she was already looking at? Its diff
      against the frame before is computed with the threshold masked out — the building,
      its roof and its doorstep, which is where the hut becomes the room — and must be
      near zero everywhere else.

Exit status 0 when every scenario passes both, 1 otherwise. Usage:

    python3 tools/measure_door_transition.py            # the table and the verdict
    python3 tools/measure_door_transition.py --json     # the numbers, for a test to read
"""
import json
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "door_transition")

# (a) a step is a jump when it is this many times the larger of its two neighbours
# and at least JUMP_PX on its own — the floor keeps a sub-pixel wobble from counting.
# The first step out of a held frame is judged against the second, which an eased
# zoom keeps within about 1.2x of it.
JUMP_RATIO = 3.0
JUMP_PX = 4.0
# (b) a frame's diff is a spike when it is this many times the median diff of the
# four frames on either side of it (the larger of the two sides). A slow, eased
# zoom's diff is small and jittery — pixel art crossing texel boundaries under a
# sub-pixel creep changes many pixels on one frame and few on the next, two- to
# threefold between neighbours — while a cut or a content pop stands ten times
# above the frames around it. The camera's own continuity is (a)'s to judge, to a
# third of a pixel.
SPIKE_RATIO = 3.0
# ...and at least this large: below it a hen's step or a crop's nod is the whole diff.
SPIKE_FLOOR = 5.0
SPIKE_SPAN = 4
# (c) the swap frame is drawn from the picture she was already looking at, so the
# diff between it and the frame before — outside the building that becomes the
# room — is at most a subpixel wobble on whatever was moving.
SWAP_MAX = 1.5


def load_frames(scn_dir, n):
    return [np.asarray(Image.open(os.path.join(scn_dir, "f%03d.png" % i)).convert("RGB"),
                       dtype=np.int16) for i in range(n)]


def footprint_mask(sample, frame, shape):
    """Screen pixels the building (and, indoors, the room that replaces it) covers on
    this frame. None when there is no room mapping to read it from."""
    room = sample.get("room") or {}
    if not room:
        return None
    a, b, c, d, tx, ty = frame["xf"]
    pitch = room["pitch"]
    ox, oy = room["offset"]
    bx, by = room["building_tile"]
    bw, bh = room["building_size"]
    # the building, its roof's row above, and the doorstep row below: the threshold
    corners = [(bx * 16, (by - 1) * 16), ((bx + bw) * 16, (by + bh + 1) * 16)]
    if frame["room"]:
        corners = [(ox + x * pitch, oy + y * pitch) for x, y in corners]
    boxes = [corners]
    # ...and the farmer herself, wherever the door put her down: her 48x48 sprite
    # hangs from her feet at (-24, -32), and a door can let out of a side when the
    # doorstep is blocked.
    px_, py_ = frame["player_tile"]
    her = [((px_ + 0.5) * 16 - 24, (py_ + 0.5) * 16 - 32), ((px_ + 0.5) * 16 + 24, (py_ + 0.5) * 16 + 16)]
    if frame["room"]:
        her = [(ox + x * pitch, oy + y * pitch) for x, y in her]    # hmm: indoors her tile is a room cell
    boxes.append(her)
    h, w = shape[:2]
    m = np.ones((h, w), dtype=bool)
    for box in boxes:
        pts = [(a * x + c * y + tx, b * x + d * y + ty) for x, y in box]
        x0, x1 = sorted(p[0] for p in pts)
        y0, y1 = sorted(p[1] for p in pts)
        xs, xe = max(0, int(x0) - 2), min(w, int(x1) + 3)
        ys, ye = max(0, int(y0) - 2), min(h, int(y1) + 3)
        if xe > xs and ye > ys:
            m[ys:ye, xs:xe] = False
    return m


def analyse(name, sample):
    frames = sample["frames"]
    n = len(frames)
    swap = sample["swap_frame"]
    imgs = load_frames(os.path.join(OUT, name), n)

    # (a) the landmark's screen path
    pts = np.array([f["landmark_screen"] for f in frames], dtype=float)
    steps = np.linalg.norm(np.diff(pts, axis=0), axis=1)   # steps[k] = frame k -> k+1
    worst = None
    for k in range(len(steps)):
        nb = [steps[j] for j in (k - 1, k + 1) if 0 <= j < len(steps)]
        ref = max(nb) if nb else 0.0
        ratio = steps[k] / ref if ref > 1e-6 else (float("inf") if steps[k] > JUMP_PX else 0.0)
        if worst is None or ratio > worst["ratio"]:
            worst = {"frame": k + 1, "step_px": float(steps[k]), "ratio": float(ratio)}
    jump = worst["step_px"] >= JUMP_PX and worst["ratio"] >= JUMP_RATIO

    # (b) consecutive-frame diffs, whole picture and with the building masked.
    # diffs[k] is the change between frame k-1 and frame k.
    diffs = [0.0]
    diffs_masked = [0.0]
    for k in range(1, n):
        d = np.abs(imgs[k] - imgs[k - 1]).mean(axis=2)
        diffs.append(float(d.mean()))
        m = footprint_mask(sample, frames[k], d.shape)
        diffs_masked.append(float(d[m].mean()) if m is not None else float(d.mean()))
    diffs = np.array(diffs)
    diffs_masked = np.array(diffs_masked)

    def spike(arr):
        worst = {"frame": swap, "peak": float(arr[swap]), "ratio": 0.0}
        for k in range(1, n):
            before = arr[max(1, k - SPIKE_SPAN):k]
            after = arr[k + 1:k + 1 + SPIKE_SPAN]
            ref = max(float(np.median(before)) if len(before) else 0.0,
                      float(np.median(after)) if len(after) else 0.0)
            ratio = arr[k] / ref if ref > 1e-9 else (float("inf") if arr[k] >= SPIKE_FLOOR else 0.0)
            if arr[k] >= SPIKE_FLOOR and ratio > worst["ratio"]:
                worst = {"frame": k, "peak": float(arr[k]), "ratio": float(ratio)}
        worst["spike"] = bool(worst["peak"] >= SPIKE_FLOOR and worst["ratio"] >= SPIKE_RATIO)
        return worst

    whole = spike(diffs)
    masked = spike(diffs_masked)
    swap_pop = {"whole": float(diffs[swap]), "outside_building": float(diffs_masked[swap]),
                "pop": bool(diffs_masked[swap] > SWAP_MAX)}
    return {
        "went_through": sample["went_through"],
        "frames": n,
        "swap_frame": swap,
        "zoom_start": frames[swap]["zoom"],
        "zoom_end": frames[-1]["zoom"],
        "landmark": {"worst_frame": worst["frame"], "step_px": worst["step_px"],
                     "ratio": worst["ratio"], "jump": bool(jump),
                     "steps_px": [round(float(s), 2) for s in steps]},
        "diff_whole": whole,
        "diff_masked": masked,
        "swap": swap_pop,
        "diffs": [round(float(x), 3) for x in diffs],
        "pass": bool(sample["went_through"] and not jump and not whole["spike"]
                     and not swap_pop["pop"]),
    }


def main():
    with open(os.path.join(OUT, "samples.json")) as f:
        data = json.load(f)
    results = {name: analyse(name, s) for name, s in data["scenarios"].items()}
    if "--json" in sys.argv:
        print(json.dumps(results, indent=1))
    else:
        print("%-9s %-8s %-22s %-22s %-24s %s" % (
            "door", "through", "landmark: worst step", "picture: worst frame",
            "swap frame diff (outside)", "verdict"))
        for name, r in results.items():
            lm, dw, sw = r["landmark"], r["diff_whole"], r["swap"]
            print("%-9s %-8s f%02d %6.1f px x%-5.1f  f%02d %6.2f x%-5.1f      %6.2f (%6.2f)          %s" % (
                name, "yes" if r["went_through"] else "NO",
                lm["worst_frame"], lm["step_px"], min(lm["ratio"], 999),
                dw["frame"], dw["peak"], min(dw["ratio"], 999),
                sw["whole"], sw["outside_building"],
                "pass" if r["pass"] else "FAIL"))
        print("the far side is first drawn on frame f%02d. A jump is a step >= %.0f px and %.0fx its "
              "neighbours; a spike is a frame diff %.0fx the frames around it; the swap frame may differ "
              "from the one before by at most %.1f outside the building."
              % (next(iter(results.values()))["swap_frame"], JUMP_PX, JUMP_RATIO,
                 SPIKE_RATIO, SWAP_MAX))
    passed = sum(1 for r in results.values() if r["pass"])
    if "--json" not in sys.argv:
        print("Doors: %d passed, %d failed" % (passed, len(results) - passed))
    sys.exit(0 if passed == len(results) else 1)


if __name__ == "__main__":
    main()
