# Rescued from the retired `com.godot.game` build

This session was not pulled by `tools/pull_session.sh`. It was rescued by hand on
2026-09-02 from the tablet's *old* installation — package `com.godot.game`, app label
`godot-project-name-en`, the Godot export defaults from before the package was renamed
to `com.daniel.tinyfarm` — immediately before that installation was uninstalled.

It is kept for the same reason the others are: a playtest is not repeatable, and this is
the oldest surviving one (2026-08-21, a week before the earliest session in this
directory).

Two caveats on how far it can be trusted:

- **There is no `session_trace.jsonl`.** That build did not write one yet, so the taps
  that did nothing — the most useful part of a playtest — are gone. Only the actions that
  changed the world survive.
- **The replay predates Q-41's `build_id` stamp** (its header carries only `base_save`,
  `gen_seed` and `version`), so there is no way to say which code produced it, and
  `verify_replay.gd` should not be expected to reproduce the autosave: the rules the
  actions were recorded against have since changed. Read it as history, not as a
  regression fixture.
