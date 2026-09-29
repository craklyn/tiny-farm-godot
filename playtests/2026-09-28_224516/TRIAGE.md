# Manual triage, 2026-09-28 — installed over deliberately

Rescued from the tablet by the deploy (recorded under v0.2.0.1-634-g1e1c1f4, i.e. 1e1c1f4). Checked
under that exact build with `tools/verify_replay.gd`:

    MISMATCH: recomputation diverged from the recording.
    entry 704: recorded @65459 {actor=bot_mk3,target=10,8,verb=water},
               recomputed @65409 {actor=bot_mk3,target=11,9,verb=till}
    MISMATCH: replay end state differs from autosave.

**The action mismatch is the checker bug already fixed on 2026-09-25.** 1e1c1f4
predates cc288db ("Stop a play session's replay failing when the game rejects a
robot's action"): the checker compared refused robot actions against the
recording. With only cc288db's change to `systems/sim/replay_log.gd` applied to
1e1c1f4, the recomputation no longer diverges.

**The end-state difference was presentation state, not farm state.** Under
1e1c1f4 plus the checker fix, the first differing field is
`state.story_loops_shown.robot_night`: the replay has no entry and the autosave
has `true`. The presentation layer sets this once-per-farm guard when it chooses
the robot-night animation, after the sleep Action has advanced the simulation.
A replay applies simulation Actions without running that animation, so it
correctly cannot reproduce the flag. The verifier now excludes the guard, as it
already excludes the selected tool and seed, and this session matches under
1e1c1f4 plus cc288db.

This diagnosis was reproduced on 2026-09-29 in a fresh tree extracted from
1e1c1f4, with cc288db's `systems/sim/replay_log.gd` and the diagnostic verifier
applied. Before excluding the guard, the verifier reported:

    first difference: state.story_loops_shown.robot_night: missing from replay; autosave has true

After excluding the guard, a subsequent verifier run in the same preserved tree
exited 0 and reported:

    MATCH: replay reproduces the autosave state exactly.

The farm itself is not affected: an install does not touch the autosave on the
tablet, and all three files are kept here. `verification.sha256` beside this note
is therefore a triage receipt, not a passed verification — it lets the deploy
install today's build (Daniel asked for it on 2026-09-28) without re-litigating
this session.
