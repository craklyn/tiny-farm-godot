# Not a playtest — the farm that was on the tablet the morning of the deploy

Pulled off the tablet on 2026-09-16 just before the save-slot build was installed, so
that installing could not be the thing that lost it. It is a **day-4 farm on its own
seed**, started that morning over the top of the day-31 farm in
`playtests/2026-09-15_234314/` — which is the play session, and which was put back into
slot 1 the same day with `tools/push_session.sh`.

Its trace holds a single tap, so it says nothing about how anyone plays. It is kept
because it is a real farm somebody made and the device no longer holds it alone: it now
lives in slot 2 of the tablet and here.

Deliberately not classified in `tests/test_runner.gd`'s `SHELF` — that list is for play
sessions, and being unclassified is skipped rather than failed.
