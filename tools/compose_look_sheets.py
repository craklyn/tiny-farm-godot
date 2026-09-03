#!/usr/bin/env python3
"""Turn a look session's raw captures into one labelled sheet per question.

Q-86, the designer 2026-09-02: *"Each step should draw a scenario under specific
conditions, and then quiz me. It shouldn't be something so opaque and require
heavy manual intervention."* `tools/capture_looks.tscn` does the staging and the
photography; this does the part that makes a picture into a question — crops each
draft to the thing being asked about, blows it up so a two-pixel difference is a
difference you can see, and puts the question on top in the words it would be
asked in.

    godot --path . res://tools/capture_looks.tscn     # stage and photograph
    python3 tools/compose_look_sheets.py              # label and compose

Writes `sheet.png` (the drafts side by side, one frame each) and, where a
scenario asked for a strip, `motion.png` (each draft twice, a beat apart) into the
same folder as the captures. Both are regenerable and gitignored.

Then it **delivers**. A decision card in HQ asks for a sheet by citing the
scenario — `{"type": "look", "scenario": "already_done"}` in its `attachments` —
and every cited sheet is copied into `hq/data/looks/<scenario>/` with a small
`look.json` beside it, which is what HQ serves on the card. Those copies are
committed, which is exactly what the gitignore means by "a sheet is committed
only when it is attached to a decision": the rig's output stays disposable and
the delivered evidence is version-controlled with the card that cites it.

The join runs card -> scenario and not the other way round. A scenario is a
question about the game and should not have to know which card is asking it;
one sheet can be evidence on several cards, and a card can be retired without
editing the rig.

Idempotent, costs nothing, needs no network.
"""
import datetime
import json
import os
import shutil
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOOKS = os.path.join(ROOT, "tools", "looks")
DECISIONS = os.path.join(ROOT, "hq", "data", "decisions")
PUBLISHED = os.path.join(ROOT, "hq", "data", "looks")

FONT_DIR = "/usr/share/fonts/truetype/dejavu"
SCALE = 2          # nearest-neighbour, so pixel art stays pixel art
PAD = 24
GAP = 20
BG = (18, 22, 20)
INK = (238, 240, 234)
DIM = (150, 165, 152)
ACCENT = (255, 219, 115)


def font(name, size):
    path = os.path.join(FONT_DIR, name)
    if os.path.exists(path):
        return ImageFont.truetype(path, size)
    return ImageFont.load_default()


F_Q = font("DejaVuSans-Bold.ttf", 26)
F_NOTE = font("DejaVuSans.ttf", 16)
F_NAME = font("DejaVuSans-Bold.ttf", 19)
F_BLURB = font("DejaVuSans.ttf", 15)


def wrap(draw, text, fnt, width):
    """Greedy wrap to a pixel width. Returns a list of lines."""
    words, lines, line = text.split(), [], ""
    for w in words:
        trial = (line + " " + w).strip()
        if draw.textlength(trial, font=fnt) <= width or not line:
            line = trial
        else:
            lines.append(line)
            line = w
    if line:
        lines.append(line)
    return lines


def crop_panel(path, focus, size, min_top=0):
    """Crop `size` pixels around `focus`, clamped to the frame, then upscale.

    `min_top` keeps the crop below the HUD's top bar: half a bar in the corner of
    a panel reads as a broken screenshot rather than as part of the game.
    """
    img = Image.open(path).convert("RGB")
    w, h = size
    w, h = min(w, img.width), min(h, img.height)
    left = int(round(focus[0] - w / 2))
    top = int(round(focus[1] - h / 2))
    left = max(0, min(left, img.width - w))
    top = max(min_top, min(top, img.height - h))
    panel = img.crop((left, top, left + w, top + h))
    return panel.resize((w * SCALE, h * SCALE), Image.NEAREST)


def crop_rect(path, rect, width):
    """Crop a fixed rect of the frame and scale it to `width`.

    For the parts of a draft that live on the HUD: they do not move with the
    camera, so they are addressed by where they are on screen, and they are
    stacked under the panel they belong to at the panel's own width.
    """
    img = Image.open(path).convert("RGB")
    x, y, w, h = rect
    panel = img.crop((x, y, x + w, y + h))
    scale = width / panel.width
    return panel.resize((width, max(1, int(round(panel.height * scale)))), Image.NEAREST)


def compose(manifest, panels_per_draft, out_name):
    """One row of panels per draft column, captions beneath, question on top."""
    drafts = manifest["drafts"]
    if not drafts or not panels_per_draft:
        return None
    col_w = max(p.width for column in panels_per_draft for p in column)
    rows = len(panels_per_draft[0])
    col_h = sum(p.height for p in panels_per_draft[0]) + (rows - 1) * 8
    pw, ph = col_w, col_h
    total_w = PAD * 2 + col_w * len(drafts) + GAP * (len(drafts) - 1)

    scratch = ImageDraw.Draw(Image.new("RGB", (10, 10)))
    q_lines = wrap(scratch, manifest["question"], F_Q, total_w - PAD * 2)
    note_lines = wrap(scratch, manifest.get("note", ""), F_NOTE, total_w - PAD * 2) \
        if manifest.get("note") else []
    caps = []
    for d in drafts:
        caps.append(wrap(scratch, d["blurb"], F_BLURB, col_w - 8))
    cap_h = 8 + 24 + max(len(c) for c in caps) * 20 + 8

    head_h = PAD + len(q_lines) * 34 + (8 + len(note_lines) * 22 if note_lines else 0) + 12
    img_h = head_h + col_h + cap_h + PAD
    sheet = Image.new("RGB", (total_w, img_h), BG)
    draw = ImageDraw.Draw(sheet)

    y = PAD
    for line in q_lines:
        draw.text((PAD, y), line, font=F_Q, fill=INK)
        y += 34
    if note_lines:
        y += 8
        for line in note_lines:
            draw.text((PAD, y), line, font=F_NOTE, fill=DIM)
            y += 22
    y = head_h

    for i, column in enumerate(panels_per_draft):
        x = PAD + i * (col_w + GAP)
        py = y
        for panel in column:
            sheet.paste(panel, (x, py))
            py += panel.height + 8
        draw.rectangle([x - 1, y - 1, x + col_w, py - 8], outline=(60, 72, 62))
        cy = py + 2
        draw.text((x, cy), "%d.  %s" % (i + 1, drafts[i]["name"]), font=F_NAME, fill=ACCENT)
        cy += 24
        for line in caps[i]:
            draw.text((x, cy), line, font=F_BLURB, fill=DIM)
            cy += 20

    out = os.path.join(manifest["_dir"], out_name)
    sheet.save(out)
    return out


def cited_scenarios():
    """{scenario id: [decision ids]} — which sheets the cards are asking for.

    Reading the cards is what makes "committed only when attached" enforceable
    rather than a convention someone has to remember: nothing is copied into the
    repo that a card does not cite, and nothing a card cites is left undelivered.
    """
    wanted = {}
    if not os.path.isdir(DECISIONS):
        return wanted
    for name in sorted(os.listdir(DECISIONS)):
        if not name.endswith(".json"):
            continue
        with open(os.path.join(DECISIONS, name), encoding="utf-8") as fh:
            card = json.load(fh)
        for att in card.get("attachments", []):
            if att.get("type") == "look" and att.get("scenario"):
                wanted.setdefault(att["scenario"], []).append(card.get("id", name))
    return wanted


def publish(manifest, folder, asked_by):
    """Copy one scenario's sheets into HQ and describe them in `look.json`.

    The description is copied out of the capture manifest rather than restated
    here, so the question on the card is the same string the sheet was drawn
    with and the two cannot drift apart.
    """
    dest = os.path.join(PUBLISHED, manifest["id"])
    os.makedirs(dest, exist_ok=True)
    stamp = datetime.date.fromtimestamp(
        os.path.getmtime(os.path.join(folder, "manifest.json"))).isoformat()
    doc = {
        "id": manifest["id"],
        "axis": manifest["axis"],
        "question": manifest["question"],
        "note": manifest.get("note", ""),
        "captured": stamp,
        "asked_by": sorted(asked_by),
        "drafts": [{"name": d["name"], "blurb": d["blurb"]} for d in manifest["drafts"]],
    }
    for kind in ("sheet", "motion"):
        src = os.path.join(folder, kind + ".png")
        out = os.path.join(dest, kind + ".png")
        if os.path.exists(src):
            shutil.copyfile(src, out)
            doc[kind] = "%s/%s.png" % (manifest["id"], kind)
        elif os.path.exists(out):
            # A scenario that no longer strips should not leave a stale motion
            # sheet on the card claiming to show this build moving.
            os.remove(out)
    with open(os.path.join(dest, "look.json"), "w", encoding="utf-8") as fh:
        json.dump(doc, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    return dest


def main():
    if not os.path.isdir(LOOKS):
        sys.exit("no captures in tools/looks — run: godot --path . res://tools/capture_looks.tscn")
    made, composed = [], {}
    for entry in sorted(os.listdir(LOOKS)):
        folder = os.path.join(LOOKS, entry)
        mpath = os.path.join(folder, "manifest.json")
        if not os.path.exists(mpath):
            continue
        with open(mpath) as fh:
            manifest = json.load(fh)
        manifest["_dir"] = folder
        size = tuple(manifest["crop"])
        min_top = int(manifest.get("min_top", 0))

        # Each draft carries its own focus: some treatments move the camera, so
        # one measurement for the whole scenario crops them to different places.
        also = manifest.get("also_rect")
        stills = []
        for d in manifest["drafts"]:
            column = [crop_panel(os.path.join(folder, d["frames"][0]), d["focus_px"], size, min_top)]
            if also:
                column.append(crop_rect(os.path.join(folder, d["frames"][0]), also, column[0].width))
            stills.append(column)
        made.append(compose(manifest, stills, "sheet.png"))
        composed[manifest["id"]] = manifest

        if all(len(d["frames"]) > 1 for d in manifest["drafts"]):
            strips = [[crop_panel(os.path.join(folder, f), d["focus_px"], size, min_top)
                       for f in d["frames"]] for d in manifest["drafts"]]
            made.append(compose(manifest, strips, "motion.png"))

    if not made:
        sys.exit("no manifests found in tools/looks")
    for m in made:
        print("wrote %s" % os.path.relpath(m, ROOT))

    wanted = cited_scenarios()
    for sid, cards in sorted(wanted.items()):
        if sid in composed:
            dest = publish(composed[sid], os.path.join(LOOKS, sid), cards)
            print("delivered %s -> %s" % (", ".join(sorted(cards)),
                                          os.path.relpath(dest, ROOT)))
        else:
            # Loud, because the card is live in the inbox either way: he would
            # otherwise meet a decision whose evidence is silently missing.
            print("MISSING: %s cites look '%s', which this session did not "
                  "capture" % (", ".join(sorted(cards)), sid))
    if not wanted:
        print("no decision card cites a look sheet yet — nothing delivered")


if __name__ == "__main__":
    main()
