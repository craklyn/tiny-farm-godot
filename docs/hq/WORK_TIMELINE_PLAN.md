# A work card shows the whole history of its work

## The problem

One piece of work currently has two incomplete records:

- `hq/data/work/<id>.json` holds the brief, the current result and the
  conversation between Daniel and the owner.
- `hq/data/runs/workers/<run>/` holds the worker and review sessions.

The work page reads only the first record. The bullpen reads only the second.
When a drain process stops after a review but before `write_back()`, the bullpen
can show that the review rejected the result while the work card still says the
owner is working. Both views are reading real files, but neither view tells the
whole truth.

The work card should answer one question: **what has happened to this piece of
work, in order, and what happens next?** The bullpen remains the debugging view
for opening the complete session transcript.

## Design rules

1. Session files are durable evidence. Do not copy their prose into the work
   record or create a second maintained history.
2. The server joins work records and session evidence. Browsers do not infer
   workflow state independently.
3. A newer durable event outranks an older summary on the work record.
4. An interrupted run is a visible state, not an indefinitely running one.
5. Every human-authored message has a time that is available with a pointer,
   keyboard focus and touch.
6. The work card summarizes sessions. The bullpen holds their full transcripts.

## Backend

### 1. Add a per-card detail endpoint

Add `GET /api/work/<id>`. It returns the work record plus two derived fields:

```json
{
  "item": { "id": "...", "title": "...", "state": "waiting_session" },
  "effective": {
    "state": "repair_needed",
    "label": "Adam asked Yuki to verify the result in HQ",
    "at": "2026-09-22T16:37:36-07:00",
    "source": "session",
    "record_is_behind": true
  },
  "timeline": [
    {
      "id": "conversation:0",
      "kind": "comment",
      "actor": "daniel",
      "at": "2026-09-19T23:48:00-07:00",
      "body": "Why don't I see Mark III ..."
    },
    {
      "id": "20260922-161010-29c8:drain-work:finished",
      "kind": "work_finished",
      "actor": "yuki",
      "at": "2026-09-22T16:37:17-07:00",
      "summary": "Yuki returned a revised result.",
      "session": { "run": "...", "name": "..." }
    },
    {
      "id": "20260922-161010-29c8:drain-check:finding:0",
      "kind": "review_finding",
      "actor": "claude",
      "at": "2026-09-22T16:37:36-07:00",
      "summary": "The HQ page was not successfully opened in a browser.",
      "next": "Open the Entities page and confirm the card and animations render.",
      "session": { "run": "...", "name": "..." }
    },
    {
      "id": "20260922-161010-29c8:interrupted",
      "kind": "run_interrupted",
      "actor": "system",
      "at": "2026-09-22T16:37:36-07:00",
      "summary": "The build session stopped before it recorded the review on this card."
    }
  ]
}
```

The existing list endpoint can stay compact. The work page calls the detail
endpoint only for open cards, so it does not scan session logs for hundreds of
collapsed cards on every refresh.

### 2. Build the timeline from durable sources

Add a `work_timeline(item_id)` function in `hq/server.py`:

1. Load the work record.
2. Convert `conversation[]`, `prior_results[]`, the current result, amendments,
   completion and landing evidence into normalized events.
3. Find session metadata whose `item` equals the card id. Do not use the
   bullpen's 24-hour display cutoff for the card timeline.
4. Parse worker completion and the checker's structured result from the JSONL
   only when the equivalent result was not successfully written back.
5. Sort by a parsed timestamp, then by a stable phase order for equal times.
6. Deduplicate by evidence id, not by matching prose.

Session metadata should gain an `attempt_id`. `do_item()` already creates one;
pass it to `run_cli()` and write it into both the worker and reviewer metadata.
This gives the join a durable key:

```text
work item -> attempt -> worker session -> reviewer session -> write-back
```

Older sessions without an attempt id fall back to `(item, run)`.

### 3. Record the drain transaction before expensive work

The current in-memory `rec` contains the only complete link between candidate,
review, suites and write-back. Persist it after every phase to:

```text
hq/data/runs/transactions/<run>/<item>.json
```

Write by temporary file plus `os.replace()`. The record contains phase,
attempt id, candidate evidence ids, parsed review, suite result, application
result and `written_back_at`. It does not duplicate full transcripts.

The phase order is:

```text
started -> worker_finished -> review_finished -> candidate_tested
        -> applied -> verified -> written_back
```

Write `review_finished` before starting the candidate suites. In the reported
case, Adam's finding would therefore survive even if the suites or process
stop immediately afterward.

### 4. Reconcile interrupted transactions

At the start of every drain, reconcile any transaction not marked
`written_back` whose PID is dead. Run the same reconciliation once when the HQ
server starts and periodically in its existing background housekeeping loop.
The work endpoint itself stays read-only: until reconciliation completes, it
derives the effective state directly from the unfinished transaction.

- If the worker or review was incomplete, mark the transaction `interrupted`
  and clear the card's stale `started` value.
- If a review returned findings, call the existing write-back path with that
  recorded review and queue the one allowed repair.
- If tests or application are required but absent, preserve the patch and set
  the card to a truthful repair/verification state. Do not rerun a model.
- If the candidate was applied, use the existing completion-recovery evidence
  to finish recording it idempotently.

Reconciliation must be safe to run more than once. `attempt_id` and the
existing `last_recorded_attempt` guard provide the boundary.

### 5. Derive the effective state

Return both the stored state and an effective state. The effective state is
chosen from the newest durable evidence in this order:

1. A live process with matching PID: `working` or `reviewing`.
2. A completed review with findings not written back: `repair_needed`.
3. A dead unfinished transaction: `interrupted`.
4. A completed attempt awaiting application or verification:
   `verification_pending`.
5. The stored work-card state.

The UI uses `effective.state`. `record_is_behind` makes any reconciliation bug
visible instead of silently masking it.

### 6. Normalize timestamps

New writes use timezone-aware ISO 8601 with seconds, for example
`2026-09-22T16:37:36-07:00`. Continue accepting the older minute-only and
timezone-less values as local time. Do not rewrite all old records merely for
formatting.

Every timeline event gets `at`; when an old event genuinely has no recorded
time, return `at: null` and display “Time not recorded.”

## Display layer

### 1. Replace separate result and conversation blocks with one timeline

Inside an open work card, show one ordered history:

```text
Sep 19, 11:48 PM  You asked why Mark III was missing.
Sep 19, 11:49 PM  Yuki found that HQ used a different catalogue and promised a revision.
Sep 22, 4:37 PM   Yuki returned the revision.                 Open session
Sep 22, 4:37 PM   Adam found that nobody had verified it in HQ. Open review
                   Next: Yuki must open the Entities page and confirm it renders.
```

Human comments show their full bodies. Work and review events show a plain
summary and an “Open session” link to the filtered bullpen. Raw commands and
token counts remain in the bullpen.

Keep the current result prominent above the timeline only when Daniel must
judge it. While a repair is running, label the earlier result as superseded and
leave it in chronological position.

### 2. Make the card header follow the effective state

For this case the header should say:

```text
Adam asked Yuki to verify the result in HQ · 4:37 PM
```

It must not say “Yuki's second attempt is queued” after the review has already
happened. A small warning appears only when `record_is_behind`:

```text
The session ended before this card finished updating. HQ recovered its latest record.
```

That warning disappears after reconciliation writes the card successfully.

### 3. Show time without making every card noisy

For messages from today, show the local time. For older messages, show the
short date and time. The author's name carries a `<time datetime="...">`
element with the exact timestamp in its accessible label.

- Pointer: hovering the name or visible time shows the full date, time and
  timezone.
- Keyboard: focusing it shows the same text.
- Touch: tapping it opens the same small popover; tapping elsewhere closes it.

Do not make hover the only route. A “Show exact times” preference can expand
all timestamps, stored in local storage, but the compact time remains visible
without that preference. Status over time should not depend on discovering a
hidden affordance.

### 4. Keep long histories readable

Show the newest unresolved chain in full: Daniel's last comment, the owner's
response, work session, review and current next action. Fold older completed
chains under “Earlier history (N)”. Never fold away an unresolved review
finding or the event that caused the current state.

### 5. Link the two views both ways

- Each work/review event links to its exact bullpen session.
- A bullpen work group keeps “Open work card”.
- The filtered bullpen URL includes both the item and optional session key, so
  “Open review” opens Adam's panel rather than merely the group.

## Tests

### Backend

- A worker and reviewer for one item become ordered timeline events.
- A review finding is visible even when `write_back()` never ran.
- A dead PID changes a stale running transaction to `interrupted`.
- Reconciliation writes the review once and never spends another model call.
- Reconciliation is idempotent.
- Sessions older than one day remain in a card's history.
- Two attempts on one card do not merge their worker/reviewer pairs.
- Old timestamps parse as local time; new ones retain their offset.

### Display

- The card header uses effective state rather than stale stored state.
- A review finding and its next action are visible without opening the bullpen.
- “Open review” addresses the exact session.
- A timestamp is available by pointer, keyboard and touch.
- The newest unresolved chain never folds away.
- A missing timestamp displays “Time not recorded.”

### End-to-end recovery scenario

Add a canary that writes a completed worker session and a review with findings,
leaves the transaction before `write_back()`, and uses a dead PID. The work
endpoint must immediately report `repair_needed`; reconciliation must then
update the card and queue the repair without invoking a model.

## Delivery order

1. Persist transaction checkpoints and add reconciliation.
2. Add attempt ids to session metadata.
3. Add the per-card detail endpoint and timeline builder.
4. Render effective state and the unified timeline on work cards.
5. Add accessible timestamps and exact-session links.
6. Remove the old separate conversation rendering after the new path covers
   old records.

The first two steps fix the trust failure even before the visual redesign
lands. The later steps make the recovered truth understandable on the card
where Daniel is already looking.
