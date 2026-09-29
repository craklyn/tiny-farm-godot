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

**The end-state difference remains, and is not explained here.** Under 1e1c1f4 plus
the checker fix, the verifier still reports "replay end state differs from
autosave", without saying which part differs. It is filed as its own work card.

The farm itself is not affected: an install does not touch the autosave on the
tablet, and all three files are kept here. `verification.sha256` beside this note
is therefore a triage receipt, not a passed verification — it lets the deploy
install today's build (Daniel asked for it on 2026-09-28) without re-litigating
this session.
