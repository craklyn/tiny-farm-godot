#!/usr/bin/env python3
"""record_sound_candidates.py — the Q-107 comparison: each story-night moment
recorded once per candidate sound, one sound swapped at a time against the
wired picks, so the designer hears the pick beside its rivals in the same
place (the rule: a recommended pick is shown beside the alternatives it beat,
in the same form).

Needs a display and ffmpeg. Writes docs/design/mockups/story_night_sounds/
<slot>__<candidate>.mp4 and rewrites the Q-107 card's attachments to match, so
the card and the clips on disk never disagree.

    python3 tools/record_sound_candidates.py            # all slots
    python3 tools/record_sound_candidates.py peck       # one slot
"""
import json, os, subprocess, sys, tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = "docs/design/mockups/story_night_sounds"
CARD = "hq/data/decisions/Q-107.json"
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

# slot -> (segment, plain name, when it plays, how many of the leading
# candidates are wired (systems/audio_manager.gd), [(candidate file stem,
# description)]). The wired count is 1 for every slot except the servo, which
# ships two takes as alternating variants (Q-107, 2026-09-11) — both lead the
# list and both are tagged "the pick" rather than one reading as an alternate
# to the other.
SLOTS = {
    "peck": ("crow_night", "The crow's peck", "on each of her two strikes", 1, [
        ("peck_cc0_248254", "“Pecked eyeball” by jameswrowles, a free recording"),
        ("peck_synth", "synthesized: two sharp tocs"),
    ]),
    "seeder_tread": ("robot_night", "The robot's treads", "only while it is shown driving", 1, [
        ("seeder_tread_cc0_415564", "“mehackit robot 5” by hullum, a free recording"),
        ("seeder_tread_cc0_425271", "“Tank Tread” by 77Pacer, a free recording"),
        ("seeder_tread_cc0_415565", "“mehackit robot 6” by hullum, a free recording"),
    ]),
    "seeder_servo": ("robot_night", "The robot's servo", "as the arm swings, alternating each time", 2, [
        ("seeder_servo_cc0_740245", "“Servo 7” by JoontheFloof, a free recording"),
        ("seeder_servo_cc0_740247", "“Servo 9” by JoontheFloof, a free recording"),
        ("seeder_servo_cc0_740244", "“Servo 6” by JoontheFloof, a free recording"),
    ]),
    "seeder_scatter": ("robot_night", "The seed scatter", "as the seed lands", 1, [
        ("seeder_scatter_cc0_348953", "“Crumble 6” by abstraktgeneriert, a free recording"),
        ("seeder_scatter_cc0_348954", "“Crumble 9” by abstraktgeneriert, a free recording"),
        ("seeder_scatter_cc0_348955", "“Crumble 8” by abstraktgeneriert, a free recording"),
    ]),
    "bloom_chime": ("boot", "The chime under the bloom", "as the seeds rise at boot", 1, [
        ("bloom_chime", "synthesized: a five-note rise sized to the bloom"),
        ("bloom_chime_cc0_333694", "“Thin bell ding 3” by Khrinx, a free recording"),
        ("bloom_chime_cc0_333695", "“Thin bell ding 2” by Khrinx, a free recording"),
        ("bloom_chime_cc0_333696", "“Thin bell ding 1” by Khrinx, a free recording"),
    ]),
}


def record(segment, slot, cand, label, out_mp4, tmp):
    avi = os.path.join(tmp, f"{slot}__{cand}.avi")
    txt = os.path.join(tmp, f"{slot}__{cand}.txt")
    with open(txt, "w") as f:
        f.write(label)
    subprocess.run(["godot", "--path", ".", "--write-movie", avi, "--fixed-fps", "30",
                    "res://tools/record_story_sounds.tscn", "--", segment, f"{slot}={cand}"],
                   cwd=REPO, check=True, capture_output=True, timeout=600)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", avi,
                    "-vf", f"drawtext=fontfile={FONT}:textfile={txt}:x=12:y=12:fontsize=18:"
                           "fontcolor=white:box=1:boxcolor=black@0.55:boxborderw=6",
                    "-c:v", "libx264", "-preset", "medium", "-crf", "27", "-pix_fmt", "yuv420p",
                    "-r", "30", "-c:a", "aac", "-b:a", "96k", "-ar", "44100", "-ac", "2", out_mp4],
                   cwd=REPO, check=True, timeout=600)
    os.remove(avi)


def main():
    want = sys.argv[1:] or list(SLOTS)
    os.makedirs(os.path.join(REPO, OUT), exist_ok=True)
    tmp = tempfile.mkdtemp()
    attachments = [
        {"type": "heading", "caption": "All five picks in one pass",
         "detail": "the boot, the crow night, the robot night — what ships today"},
        {"type": "video", "src": "docs/design/mockups/story_night_sounds.mp4", "tag": "the pick",
         "caption": "The boot (the chime, then a pause, then the music rising), the crow night (squawk, two pecks, the music ducked), the robot night (treads while it drives, servo, seed scatter)."},
    ]
    for slot, (segment, name, when, wired_count, cands) in SLOTS.items():
        attachments.append({"type": "heading", "caption": name,
                            "detail": f"{when} — the same moment once per candidate, only this sound changed"})
        for i, (cand, desc) in enumerate(cands):
            if i < wired_count:
                tag = "the pick" if wired_count == 1 else f"the pick (take {i + 1} of {wired_count})"
            else:
                tag = f"alternate {i - wired_count + 1} of {len(cands) - wired_count}"
            out_rel = f"{OUT}/{slot}__{cand}.mp4"
            if slot in want:
                label = f"{name} · {tag} · {desc}"
                record(segment, slot, cand, label, os.path.join(REPO, out_rel), tmp)
                print("wrote", out_rel, flush=True)
            attachments.append({"type": "video", "src": out_rel, "tag": tag, "caption": desc})
    card = json.load(open(os.path.join(REPO, CARD)))
    card["attachments"] = attachments
    with open(os.path.join(REPO, CARD), "w") as f:
        json.dump(card, f, indent=1, ensure_ascii=False)
        f.write("\n")
    print("card attachments rewritten:", len(attachments))


if __name__ == "__main__":
    main()
