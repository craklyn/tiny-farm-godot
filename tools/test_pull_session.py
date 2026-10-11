#!/usr/bin/env python3
"""Which farms tools/pull_session.sh takes off the tablet, against a stand-in tablet.

No tablet and no Godot are needed. A fake `adb` answers from a scratch folder laid
out like the game's internal storage (`files/slot1` .. `files/slot3`), reports an
install time, and runs the script's remote commands locally. The script is the
real one, pointed at a scratch shelf through PLAYTESTS_DIR.

The case that matters is the night of 2026-10-09: the farm being played had a short
trace since it was last opened, another slot still held an older, longer trace from
September, and the old rule (longest trace wins) shelved the September farm in its
place. Here the played farm is taken as new play, and the September farm is taken
too but labelled as the older play it is. The rest are the ways the pull must stop
rather than guess: a tablet that does not answer, a file that does not arrive.
"""

from __future__ import annotations

import calendar
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools" / "pull_session.sh"
PKG = "com.daniel.tinyfarm"

# Stands in for adb. `-s <serial> shell|exec-out "<command>"` runs the command in the
# fake app folder (dropping `run-as <pkg>`, which is how the real one gets there),
# except `dumpsys package`, which prints the install time the test chose. A command
# containing any of the `|`-separated texts in the folder's `fail` file fails the way
# adb does when the connection drops: an error and nothing on stdout.
FAKE_ADB = r'''#!/usr/bin/env python3
import os, subprocess, sys
args = sys.argv[1:]
device = os.environ["FAKE_TABLET"]
fail_file = os.path.join(device, "fail")
failing = open(fail_file).read().split("|") if os.path.exists(fail_file) else []
if any(f and f in " ".join(args) for f in failing):
    sys.stderr.write("error: closed\\n")
    sys.exit(1)
if args[:1] == ["devices"]:
    print("List of devices attached")
    print("stand-in-tablet\tdevice")
    sys.exit(0)
if args[:1] in (["start-server"], ["connect"], ["mdns"]):
    sys.exit(0)
if args[:1] == ["-s"]:
    args = args[2:]
if args[:1] not in (["shell"], ["exec-out"]):
    sys.exit(1)
command = " ".join(args[1:])
if command.startswith("dumpsys package"):
    stamp = os.path.join(device, "installed_at")
    if os.path.exists(stamp):
        print("    lastUpdateTime=" + open(stamp).read().strip())
    sys.exit(0)
prefix = "run-as %s " % "''' + PKG + r'''"
if command.startswith(prefix):
    command = command[len(prefix):]
sys.exit(subprocess.call(["sh", "-c", command], cwd=os.path.join(device, "app")))
'''

TAP = {"kind": "tap", "in": "tap", "tile": [3, 4], "at": [2, 4], "tool": 0,
       "verb": "till", "out": "acted"}


def compact(value: dict) -> str:
    return json.dumps(value, separators=(",", ":"))  # as the game writes it


def trace(taps: int, salt: str) -> str:
    lines = [compact({"version": 1, "gen_seed": 0, "continued": True, "salt": salt})]
    lines += [compact(dict(TAP, t=i * 500)) for i in range(taps)]
    return "\n".join(lines) + "\n"


def epoch(stamp: str) -> int:
    return calendar.timegm(time.strptime(stamp, "%Y-%m-%d %H:%M:%S"))


class PullSessionTest(unittest.TestCase):
    INSTALLED = "2026-10-09 18:00:00"

    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="pull-session-test-"))
        self.tablet = self.tmp / "tablet"
        (self.tablet / "app" / "files").mkdir(parents=True)
        self.shelf = self.tmp / "playtests"
        self.shelf.mkdir()
        tools = self.tmp / "sdk" / "platform-tools"
        tools.mkdir(parents=True)
        adb = tools / "adb"
        adb.write_text(FAKE_ADB)
        adb.chmod(0o755)
        self.result = self.tmp / "result.txt"
        self.set_install_time(self.INSTALLED)

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def set_install_time(self, stamp: str | None) -> None:
        path = self.tablet / "installed_at"
        if stamp is None:
            path.unlink(missing_ok=True)
        else:
            path.write_text(stamp)

    def farm(self, where: str, written: str, taps: int, salt: str | None = None) -> None:
        """A farm on the tablet whose files were last written at `written`."""
        folder = self.tablet / "app" / "files" / where
        folder.mkdir(parents=True, exist_ok=True)
        files = {
            "session_trace.jsonl": trace(taps, salt or where + written),
            "session_replay.json": json.dumps({"version": 4, "build_id": "test-build"}) + "\n",
            "autosave.json": json.dumps({"state": {"slot": where}}),
        }
        for name, text in files.items():
            (folder / name).write_text(text)
            os.utime(folder / name, (epoch(written), epoch(written)))

    def fail_on(self, *texts: str) -> None:
        (self.tablet / "fail").write_text("|".join(texts))

    def pull(self, *args: str, ok: bool = True) -> subprocess.CompletedProcess:
        env = dict(os.environ,
                   ANDROID_HOME=str(self.tmp / "sdk"),
                   FAKE_TABLET=str(self.tablet),
                   PLAYTESTS_DIR=str(self.shelf),
                   PULL_SESSION_RESULT_FILE=str(self.result),
                   GODOT="true",
                   TZ="UTC")
        run = subprocess.run(["bash", str(SCRIPT), *args], env=env, cwd=ROOT,
                             capture_output=True, text=True, timeout=60)
        if ok:
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        else:
            self.assertNotEqual(run.returncode, 0, run.stdout + run.stderr)
        return run

    def shelved(self) -> list[str]:
        """What each shelved folder says it is: `slot1`, `slot3_from-2026-09-25`."""
        return sorted(p.name.split("_", 2)[2] for p in self.shelf.iterdir())

    def reported(self) -> list[tuple[str, str]]:
        """(kind, folder name) for each line the deploy is handed."""
        lines = [line.split("\t") for line in self.result.read_text().splitlines() if line]
        return [(kind, Path(folder).name) for kind, folder in lines]

    def kinds(self) -> list[tuple[str, str]]:
        return sorted((kind, name.split("_", 2)[2]) for kind, name in self.reported())

    # --- which farms, and what kind ------------------------------------------

    def test_every_farm_with_unsaved_play_is_taken_and_the_stale_one_is_labelled(self) -> None:
        # 2026-10-09 again: slot 1 played a little since the install, slot 3 holding
        # a longer trace from September that no rescue took. Slot 1 must be taken as
        # tonight's play; slot 3 is taken too, but labelled as the older play it is.
        self.farm("slot1", "2026-10-09 21:40:00", taps=3)
        self.farm("slot2", "2026-10-09 19:10:00", taps=40)
        self.farm("slot3", "2026-09-25 10:14:00", taps=80)
        run = self.pull()
        self.assertEqual(self.kinds(), [("new", "slot1"), ("new", "slot2"),
                                        ("older", "slot3_from-2026-09-25")], run.stdout)
        self.assertIn("files/slot3: older play no rescue has taken", run.stdout)
        for folder in self.shelf.iterdir():
            slot = folder.name.split("_")[2]
            self.assertEqual(json.loads((folder / "autosave.json").read_text())["state"]["slot"],
                             slot, "each folder holds the farm its name says")
            for name in ("session_trace.jsonl", "session_replay.json", "autosave.json"):
                self.assertTrue((folder / name).is_file(), f"{folder.name} has {name}")

    def test_a_stale_farm_already_on_the_shelf_is_left_alone_quietly(self) -> None:
        self.farm("slot3", "2026-09-25 10:14:00", taps=8)
        self.pull()
        self.assertEqual(self.kinds(), [("older", "slot3_from-2026-09-25")])
        self.farm("slot1", "2026-10-09 21:40:00", taps=3)
        run = self.pull()
        self.assertEqual(self.kinds(), [("new", "slot1")], "nothing more to say about slot 3")
        self.assertIn("files/slot3: already on the shelf", run.stdout)

    def test_a_farm_already_on_the_shelf_is_named_not_filed_twice(self) -> None:
        self.farm("slot1", "2026-10-09 21:40:00", taps=5)
        self.pull()
        first = self.reported()
        self.assertEqual(self.shelved(), ["slot1"])
        run = self.pull()
        self.assertEqual(self.shelved(), ["slot1"], "the same play is not shelved twice")
        self.assertEqual(self.reported(), first, "the deploy is told where it already is")
        self.assertIn("already on the shelf", run.stdout)

    def test_a_farm_opened_but_not_tapped_is_not_a_playtest(self) -> None:
        self.farm("slot2", "2026-10-09 21:40:00", taps=0)
        run = self.pull()
        self.assertEqual(self.shelved(), [])
        self.assertEqual(self.reported(), [])
        self.assertIn("no taps in the trace", run.stdout)

    def test_nothing_unsaved_pulls_nothing(self) -> None:
        self.farm("slot1", "2026-10-09 21:40:00", taps=50)
        self.pull()
        self.result.write_text("left over from another run\n")
        run = self.pull()
        self.assertEqual(self.shelved(), ["slot1"])
        self.assertIn("Nothing to pull", run.stdout)

    def test_slot_option_takes_one_farm_by_hand(self) -> None:
        self.farm("slot1", "2026-10-09 21:40:00", taps=5)
        self.farm("slot3", "2026-09-25 10:14:00", taps=8)
        self.pull("--slot", "3")
        self.assertEqual(self.shelved(), ["slot3_from-2026-09-25"])

    def test_a_tablet_from_before_slots_still_has_its_farm_taken(self) -> None:
        self.farm(".", "2026-10-09 21:40:00", taps=5)
        self.pull()
        self.assertEqual(self.shelved(), ["before-slots"])

    # --- the install time ------------------------------------------------------

    def test_without_an_install_time_all_play_is_new(self) -> None:
        self.set_install_time(None)
        self.farm("slot1", "2026-10-09 21:40:00", taps=5)
        self.farm("slot3", "2026-09-25 10:14:00", taps=8)
        run = self.pull()
        self.assertEqual(self.kinds(), [("new", "slot1"), ("new", "slot3")])
        self.assertIn("did not give a usable install time", run.stdout)

    def test_an_install_time_after_the_tablets_own_clock_is_not_trusted(self) -> None:
        # A clock that was ahead at install would otherwise make every later play
        # look older than the install.
        self.set_install_time("2099-01-01 00:00:00")
        self.farm("slot1", "2026-10-09 21:40:00", taps=5)
        run = self.pull()
        self.assertEqual(self.kinds(), [("new", "slot1")])
        self.assertIn("did not give a usable install time", run.stdout)

    def test_play_during_a_deploy_is_taken_before_the_install(self) -> None:
        # The deploy rescues, builds for minutes, then rescues again just before it
        # installs. Play in between is new to the second rescue.
        self.farm("slot1", "2026-10-09 21:40:00", taps=5)
        self.pull()
        first = self.reported()
        self.farm("slot1", "2026-10-09 21:44:00", taps=9, salt="played during the build")
        self.pull()
        second = self.reported()
        self.assertEqual([kind for kind, _ in second], ["new"])
        self.assertNotEqual(second, first, "the second rescue reports the new sitting")
        latest = self.shelf / second[0][1] / "session_trace.jsonl"
        self.assertIn("played during the build", latest.read_text())
        self.assertEqual(len(list(self.shelf.iterdir())), 2, "both sittings are on the shelf")

    def test_play_that_slipped_past_both_rescues_is_still_taken_next_time(self) -> None:
        # Played in the seconds between the last rescue and the install: written
        # before the new install time, and on no shelf. It is taken as older play.
        self.farm("slot1", "2026-10-09 17:59:30", taps=5)
        self.pull()
        self.assertEqual(self.kinds(), [("older", "slot1_from-2026-10-09")])

    # --- failing closed --------------------------------------------------------

    def test_a_trace_that_does_not_come_across_stops_the_pull(self) -> None:
        # The probe saw slot 1's trace; the copy then fails. That is a failed pull,
        # not a farm nobody touched, and the deploy must not install over it.
        self.farm("slot1", "2026-10-09 21:40:00", taps=5)
        self.fail_on("cat files/slot1/session_trace.jsonl")
        run = self.pull(ok=False)
        self.assertIn("did not come across", run.stderr)
        self.assertNotIn("nobody touched", run.stdout)

    def test_a_played_farm_missing_its_save_stops_the_pull(self) -> None:
        self.farm("slot1", "2026-10-09 21:40:00", taps=5)
        self.fail_on("cat files/slot1/autosave.json")
        run = self.pull(ok=False)
        self.assertIn("replay or autosave did not come across", run.stderr)
        self.assertEqual(self.reported(), [])
        kept = list(self.shelf.iterdir())
        self.assertEqual(len(kept), 1, "what did arrive is kept")
        self.assertTrue((kept[0] / "session_trace.jsonl").is_file())

    def test_an_adb_failure_during_the_probe_stops_the_pull(self) -> None:
        self.farm("slot1", "2026-10-09 21:40:00", taps=5)
        self.fail_on("files/slot2/session_trace.jsonl")
        run = self.pull(ok=False)
        self.assertIn("did not answer about files/slot2", run.stderr)
        self.assertEqual(self.shelved(), [])

    def test_a_tablet_that_answers_nothing_stops_the_pull(self) -> None:
        self.farm("slot1", "2026-10-09 21:40:00", taps=5)
        self.fail_on("run-as")
        run = self.pull(ok=False)
        self.assertNotIn("Nothing to pull", run.stdout)
        self.assertEqual(self.shelved(), [])


if __name__ == "__main__":
    unittest.main()
