# Keep Bullpen session history and work outcome distinct

Date: 2026-09-22
Status: IMPLEMENTED
Owner: Chief of Staff

## Problem

The Bullpen can replace its session panels when a worker stops, while retaining
the event cursor from the old panels. Opening the new, empty panel then asks the
server only for events after that cursor. The server correctly returns no new
events, and the page says “Nothing written yet” even though the durable session
log contains the whole exchange.

The same view labels every successful model process “session finished.” That
describes the process, not the work. A review which finished with a blocking
finding can therefore look like completed work until somebody reads its log.

## Design

The rendered panel is the source of truth for its event cursor. A panel with no
rendered event lines always asks from zero, even when an earlier copy of that
panel existed. A panel which remains mounted asks from the number on its last
rendered line. The empty-state message is removed before the first real line is
inserted.

The session summary names both the phase and the known outcome:

- a successful worker process says “work session finished”;
- a successful review says “review finished”;
- a review whose durable event stream contains a blocking finding says “review
  finished — changes requested”;
- failed and stopped processes keep their failure and stopped labels.

“Finished” remains a process fact. The work card remains the authority on
whether the work is active, accepted, or landed.

## Acceptance

1. Fetch a session into one panel, replace that panel with an empty copy, and
   fetch it again. Both fetches start at zero and the rebuilt panel receives the
   full history.
2. Polling a panel that already contains numbered lines asks only for later
   events.
3. A finished review with a checker finding is labelled “review finished —
   changes requested.”
4. The existing grouped disclosure and direct work-card link still work.
