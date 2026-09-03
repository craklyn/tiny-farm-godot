# Playtest sessions

Pulled off the test tablet by `tools/pull_session.sh`, one timestamped directory per
session. **Committed on purpose.** A playtest is not repeatable — the child is four once,
and the second run is a different experiment because she has already seen the game — so
these files are the M1 exit gate's evidence, not scratch data. They are small (tap
coordinates and verbs, a few KB each) and carry nothing personal.

**One folder per distinct play.** On 2026-09-02 this directory held fifteen folders for
nine plays: a deploy rescues whatever session is on the tablet, and the tablet does not
forget between deploys, so the same play kept being filed again under a new timestamp.
Five folders were removed (three byte-identical copies, and two whose replay held a
single entry on a base save while their trace was a stale copy of another session's).
`tools/pull_session.sh` now declines to shelve a duplicate trace or a tapless one, so
this cannot re-accumulate. Audit it any time:

```bash
for d in playtests/*/session_trace.jsonl; do md5sum "$d"; done | sort | uniq -c -w32 | sort -rn
```

**Read the replay, not the trace, when asking whether a session did anything.** The two
can disagree: a resumed session inherits the device's un-cleared tap trace while its own
replay records almost nothing. Two folders were mistaken for real play sessions on
exactly that confusion.

Each directory holds up to three files, and they answer different questions:

| File | Question it answers | Read it with |
|---|---|---|
| `session_trace.jsonl` | What did she tap, and what came of it — *including the taps that did nothing*? | `godot --headless --path . --script res://tools/read_trace.gd -- <path>` |
| `session_replay.json` | What actually happened to the farm? | `godot --path . tools/replay_view.tscn -- <path>` |
| `autosave.json` | Where did she end up? | `tools/verify_replay.gd` checks the replay against it |

The trace is the one to read first: `SessionTrace.summarize()` counts dead taps by reason
and flags tiles tapped three or more times with no effect, and `teaching_report()` gives
time-to-first-use per verb plus every stall over eight seconds. Those are the failures of
the *design*, not of the player.
