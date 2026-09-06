# Tiny Farm HQ

The CEO's local operating surface. The design contract: **everything is derived
from real sources (git, CI, files, docs, traces) at request time** — no page
maintains its own status, so "not marked on fire" is trustworthy, and the
dashboard's eye queue is the ordered list of what actually needs the CEO.

Surfaces: the Eye of Sauron dashboard (derived pillar statuses + the chief of
staff's brief), six pillar pages (each one the wall its VP would brief the CEO
from — see **Goals** below), org chart with chattable personas, the
animated/editable entity gallery (whose sprite editor keeps a full per-sheet
edit history and files each edit to the art director), the map editor (layout
definitions), the playtest viewer (traces scored by the game's own formulas),
the program report, and the decision inbox (curated cards + on-page rulings). The Engineering & QA
pillar page carries **The tablet** — build the code as it stands and install it on the
device, beside the "run it yourself" suites. It is the one control built to work with no
model in the loop at all, so it explains its own failures on screen (`docs/DEPLOY.md`
section 2).

- **URL:** http://localhost:8642 (on the desktop)
- **From the laptop / anywhere:** https://daniel-maco.tail445099.ts.net — the same
  server, shared tailnet-only via `tailscale serve` (set up 2026-09-02; the serve
  rule and the service both survive reboots). HQ itself stays bound to 127.0.0.1
  so the chat endpoint is never exposed beyond the tailnet. To stop sharing:
  `tailscale serve --https=443 off`.
- **Run by hand:** `python3 hq/server.py` (stdlib only, no dependencies)
- **Runs at boot:** systemd user service `tiny-farm-hq` (`~/.config/systemd/user/tiny-farm-hq.service`),
  with `loginctl enable-linger` so it starts without a login.
  - status: `systemctl --user status tiny-farm-hq`
  - logs: `journalctl --user -u tiny-farm-hq`
  - restart after editing server/data: `systemctl --user restart tiny-farm-hq`

## Goals — the one status pipeline

Every pillar's status is computed from goals it declares in
`data/goals/<pillar>.json`. There is exactly one evaluator (`eval_measure` /
`eval_goal` / `rollup` in `server.py`) and no second status system anywhere.

Before this, three pillars derived their status and three carried hardcoded
`ok` strings, so half the board could never light up however wrong things got,
and nothing on screen distinguished a measured verdict from a typed one. Sales
had a subtler version of the same bug: it only went amber when there were *zero*
release tags, so the moment `v0.1.0` existed it was structurally green forever.

**The honesty rule.** A goal's *statement* and its *target* are authored — a
commitment cannot be derived, and pretending otherwise would be the lie. Its
*current value* is measured, by a small declarative vocabulary that maps onto
things this repo really holds. A goal nothing can measure does not get to look
measured: it renders `unchecked` with the reason and the specific recording that
would make it real, and it counts **against** the pillar's assurance fraction
rather than for it. Hence the "4 of 6 checked by machine" on every pillar page —
it is what makes a green pillar with two checks visually different from a green
pillar with seven.

The six goal states: `green`, `amber`, `red` (measured), `unchecked` (nothing
watches it), `broken` (the measurement itself failed — never green; a failed
reading is a fact about the instrument), `attested` (a human declared it, with a
date, expiring). Only Daniel may attest — the rest of the org are personas, and
a persona vouching for something nothing measured would be inventing studio
activity.

**Measurement kinds** (each maps to something the audit verified exists):
`git_commits`, `git_file_age`, `git_tag`, `git_build_lag`, `file_exists`,
`file_count`, `file_grep`, `orphan_files`, `ci_state`, `job_state`,
`count_json`, `project_field`, `program_readiness`, `playtest_metric`,
`doc_section`, `queue_state`, `probe_cache`, `palette_named_present`,
`composite`, `manual_attest`, `attestation`, `unchecked`.

`attestation` is the one for gates that are human acts rather than facts about
the repo — "somebody played the web build end to end" is a person in a browser,
and no amount of reading the source finds it. It reads
`hq/data/attestations.json`, where each record names the tag it was made for and
the commit the build came from. Those two keys are what make it perishable: the
record is spent when that tag is cut, because the next release wants a different
tag and no record exists for it, and it lapses early when the game changes under
the commit it was made on. The goal row carries the button that writes it, and
the server — not the page — stamps the tag, the commit and the date, so a record
cannot claim a build nobody played. `manual_attest` is the older, simpler form:
a value typed into the goal file, expiring on a timer.

Two safety properties are structural, not conventions: **no kind executes a
shell command or opens a socket** (network readings come from `probe_cache`,
which reads a file a named background poller writes), and **every path-taking
kind goes through `_safe()`**, so a goal file cannot read outside the repo.

A `composite` with `op: all_of` is green only if every member is green *and
assured* — one unwatched member makes the whole thing unchecked. That is what
stops a nine-gate launch check from reading green because eight of the gates
were never automated.

**Rollup:** a red blocking goal is `fire`; a red important one, an amber
blocking one, a broken one, or an expired attestation is `attention`; an
unwatched blocking goal is `unassured` (never `ok`); a pillar with no goal file
is `unassured` too, because a pillar nobody has written goals for is not a
healthy pillar. Dormancy is a **flag, not a level**, so a dormant pillar with a
failing promise still reaches the nav's exception group.

`status[pid]` keeps its `{level, reasons}` contract exactly — the dashboard, the
nav dots, the standup brief and the chat personas all read it — and only gains
additive fields.

## The dot is his, so it answers his question

The dot used to answer *is anything wrong on this pillar?* — which is how a
twenty-two-item queue of ordinary work nobody had got to could light up the CEO's
board as though it were his to fix. Wrong is not the same as his. It answers one
question now: **does this pillar need him?** Four tests, and a failing goal
reaches the dot only by passing one:

| Test | It means | Where it comes from |
|---|---|---|
| **authority** | Only he can settle it — his taste, a direction, a commitment, a date, money, a credential | a recorded `ceo_blocker`, an attestation that has lapsed (only Daniel attests), or an authored `escalates` |
| **external commitment** | We have told somebody outside the studio something this contradicts, or we owe an outsider something | authored on the goal |
| **exposure** | A player or an outsider can hit this right now | authored on the goal |
| **age or trend** | Ours, but it has waited long enough — or is getting worse fast enough — that the delay is itself the news | measured |

The first three are **authored**, for the same reason a goal's statement and
target are: whether a promise was made outside this studio is not something a
measurement can discover. The fourth is **measured**, from the oldest honest
start date available — what a CEO blocker says it has been waiting, when the work
filed against it was filed, and when the goal journal first saw it non-green. A
goal with none of those has no clock and says so rather than inventing one.
Patience is 7 days on a blocking promise, 14 on an important one, 30 on a watch,
halved for anything getting worse. `data/history/goals.jsonl` is the journal —
one line an hour, written by a background thread, because a tracked file written
on page render leaves the tree dirty.

**What is deliberately not a test: needing an approval.** A tier-2 item and a
prepped decision card serve Daniel *as an approver*, and they already have two
surfaces built for answering them one after another — the Work page and the
decision inbox. Firing a pillar red because something waits on a yes makes the
board a third copy of those queues, which is how a board stops meaning anything.
Before this, any goal whose route carried a tier-2 action counted as his; that
clause is gone.

Everything that does not escalate is still measured, still on the pillar's own
page in the scoreboard, and still reaches the dashboard — as a count on the
pillar's row ("3 ours to fix") and one line in the eye queue. He should know a
pillar has work outstanding without being handed work he cannot act on.

`fire` is reserved for a reading that is actually bad *and* either aimed outward
or blocking; an attestation that has merely lapsed is `attention`. A pillar with
nothing escalated but a check that could not be read at all is `unassured`, never
`ok` — a failed reading is a fact about the instrument.

## The pillar pages

Five bands, invariant in order so the CEO learns the page once, with band 2
entirely the pillar's own because an engineering wall and an art director's wall
are not the same object:

0. identity + the assurance fraction + when it was derived
1. **the verdict** — one sentence, generated from the goals, never authored. It
   may be a *permission* rather than a status ("You cannot tag today").
2. **the instrument** — the thing only this page has. Capped at `30vh` and
   scrolling inside itself: when the screen is short the picture yields, because
   the goals and the asks matter more than the picture.
3. **the goal scoreboard** — the one band rendered identically everywhere, since
   it is what lets him compare pillars. Rows past the third fold.
4. **what I need from you** — capped at three.

Then the fold, and below it: what nobody is checking, the commit feed (demoted,
and relabelled per pillar to say what it actually measures), and the team.

**The needs band creates no records.** It is a projection over the two queues
that already exist — the decision cards and the tier-2 work items — filtered to
the pillar, ranked, capped. No ruling is ever *given* from a pillar page: a
ruling recorded in two places diverges, so every control carries him to the one
place it is recorded.

*Known limitation.* Neither queue records which pillar it belongs to, so the
projection filters by the owner's team, and a decision card with **no owner**
reaches no pillar's needs band at all. It still reaches the decision inbox,
which is the canonical surface, and a goal can point at a card explicitly
through its `ceo_blocker` — which is how the robot-menu question reaches
Marketing today. The proper fix is a `pillar` field on both record types,
defaulted from owner → team → pillar; it is deliberately not done here because
those files are written by a running service and a schema change wants its own
change.

| Pillar | Its one question | Its instrument | Its verb |
|---|---|---|---|
| Engineering | Is the proof that main works fresh enough to believe? | the evidence strip, aged in **commits behind main**, never a clock; plus 100 CI runs as ticks | RUN |
| Product | What stands in front of the next thing the player gets? | the gate scorecard welded to its build-decay stamp | CUT |
| Art | Is the game still one thing to look at? | the palette ribbon, decoded from the shipped PNGs | EDIT (gated) |
| Marketing | If people showed up tomorrow, would we know? | the promise checker: the store page vs. the build | FILL IN THE BLANK |
| Sales | What holds the next tag? | the gap, and the launch check at three-state weight | **none — no publish control, ever** |
| Ops | Can we afford what's next? | three tiles, one of which counts *down* | APPROVE |

Art's palette ribbon is the single licensed exception to *colour = semantics*,
and it says so on the page. The PNG decoding is stdlib `zlib` + `struct`, cached
on the sheets' mtimes.

## The seven rules a pillar page has to meet

These govern a page's *structure*. The words on any surface follow
[docs/WRITING.md](../docs/WRITING.md) — the studio's rules for writing to
humans, chief among them: write for the reader's incoming context, introduce a
name before using it, and state the fact rather than the observation about it.

Learned the hard way, mostly from the CEO reading the Sales page as its actual
audience rather than as its author. Any new pillar, band or instrument is held
to these.

**1. The page belongs to its audience's job, not to the data that is easy to
get.** Sales spent a day reporting a commit count, which measures how much work
happened rather than what any of it gives a player. The commit count was there
because it was the only quantity that existed — nobody had written down what the
next release offers. *When the convenient metric belongs to another seat, that is
a tell that the real record has never been built. Build the record.*

**2. Every finding carries its next action — the headline most of all.**  A row that names a problem, cites
the file and line, and stops is half a feature. Every non-green goal names an
owner and offers one control: open the project, open the card, hand it to the
pillar that owns it, or file the work. *"What is the intended user flow from
here?" is the test; if the answer is "he tells somebody in chat", it is not
finished.* This was applied to the goal rows and the needs band and **not to the
verdict**, which is the most prominent statement on the page — so the top of the
Finance page named a problem and offered nothing for two rounds of review. The
verdict now carries the same control its row does, plus the sentence saying what
is actually being asked of him ("This is a ruling only you can make", "This
wants a date from you") and what waiting costs. Where a ruling has no card
prepped, the control files the work to prepare one, because an unprepped ask is
somebody's job to prepare before it is fair to put in front of him.

**3. A check that can only ever read one way is not a check.** The ship gate
measured "the debug readout is switched off", which is red every single day by
design, because the readout is *supposed* to be on while we playtest. A status
permanently red for a good reason teaches him to ignore it. The honest check was
one level up — *nothing in the release pipeline would stop a tag shipping with it
on* — which is true until somebody fixes it and then green forever. The same
error sat in a threshold: a bar of "no more than 40 commits behind" against a
repo that commits ~33 times a day demanded a release every day and a half.
*Before shipping a check, ask what it reads today and what it reads in the normal
case. If either answer is "always", it is aimed at the wrong thing.*

**4. Nothing on the page is authored status.** The gate scorecard was five rows
written into `pillars.js` by hand — transcribed from the roadmap's scored table,
which meant it could never change, could not say which session produced it, and
would go stale the moment anybody scored the gate again. It is parsed from that
table now. *Goal statements and targets are authored, because a commitment
cannot be derived. Everything else on a pillar page is read from the thing
itself, or it says out loud that nobody is checking it.*

**5. Only what needs him reaches him.** Every finding has an owner and a tier,
and those already decide whose it is. Work the studio can just do — reading,
tracing, drafting, anything git reverts — is labelled *ours*, filed, and reaches
him as a count. Only two things earn the top of his page: something needing his
taste or authority, and something we could have fixed and left sitting long
enough that the delay is the news. The verdict band used to promote the *worst*
finding, and worst is not the same as his: tracing an unattributed sound file
was the headline on the Finance page, which spends the CEO's attention on
something that should simply have been done. *Corollary: no HQ-internal
vocabulary on a surface he reads. "A shipped asset has no ledger line" means
nothing to anybody who does not work on this codebase.*

**5b. The instrument leads with the pillar's question, not its calmest data.**
Product's page opened for weeks on the onboarding-gate scorecard — 4 of 5 bars
met, mostly fine — while the pillar's actual question is what stands in front of
the next release. A stand-up leads with the problem: the instrument now opens on
the release path and its blockers, with the gate demoted to the evidence beneath
it. Ask what the VP would put first in a fifteen-minute stand-up, not what the
code renders most readily.

**6. Report the fact; never the insight, and never the design.** A metric card
is titled for **what it counts**, and carries a denominator and a target:
"Assets missing rights clearance · 1 of 30 shipped · target 0". Not "What we
owe — counts down", footed with "the one tile in HQ where a rising number is bad
news". That is the author explaining his own encoding, and if the direction
needs explaining the target was missing. The same tic in prose: "one build is
public and the page names no contact of any kind, so the first thing a player
would tell us is the one thing we cannot hear" is a worse sentence than
"players have no way to send feedback". Design rationale belongs in the code
comments, where whoever maintains this needs it. It is never rendered.

**7. Every element is readable without instruction, and is a way in.** A chart
that needs a sentence underneath explaining how to read it has failed as a
chart; the labels go on the chart. A coloured block that only whispers a native
tooltip conveys nothing and leads nowhere; hovering shows what the thing is and
clicking opens it. And no row is a dead end — every one goes to the project, the
decision, or the story that carries it.

Two supporting habits that fall out of these:

- **The server reports facts; the page writes sentences.** The manifest once
  handed the page `"1 of 5 steps done on A stuck machine says so"` — a project
  name run into a clause with nothing marking the join. The server returns steps
  done, steps total and the project's name; the page composes the sentence and
  can make the name a link. The same mistake produced `"0.556 ratio against a
  target of 1.0 ratio"` where `"5 of 9"` was the fact.
- **Use the house vocabulary before inventing one.** Controls are `.gbtn`;
  a person's name is `[data-person]` and gets the peek every other page gives it;
  status is a `.dot` with its glyph. Blue hyperlinks and plain-text names were
  both cases of building a new thing next to an existing convention.

## Recording

Anything HQ wants to chart later has to be written down at the time, and three
of the studio's most interesting quantities had exactly one datapoint each. So:
runs stamp the commit they proved and append to `data/history/runs.jsonl`, and
the 100-run CI window is polled onto `data/ci_history.json` by a background
thread — deliberately **off** the request path, since `gh --limit 100` costs
~4s against ~1s at `--limit 10`.

**What the studio's own work costs.** Every model call the company makes
unattended — reading an exchange for the work it creates, a seat doing a tier-0
task, a drain worker, the chief of staff's check — spends the same Claude
allotment Daniel spends when he talks to HQ, and nothing recorded it:
`data/history/limits.jsonl` records the moment a five-hour window ran dry and
never what emptied it. One line per call now lands in
`data/history/tokens.jsonl` (phase, seat, model, item, tokens), which is what
lets a finished result on the Work page say what producing it spent, and lets
that page's header say what all of it has spent in the trailing five hours —
against the only measured ceiling this machine holds, which is what had been
spent the last time a window actually ran dry. A subscription publishes no token
cap, so a bar we invented would be fiction. Dollars are recorded as `list_usd`
and are the API list-price equivalent of the same tokens: an order of magnitude,
never a bill.

Nothing here is written by a request handler. A tracked file written on page
render leaves the tree dirty, and `git describe --dirty` is where playtest build
ids come from — which is exactly how two recorded sessions became impossible to
tie to a build.

## Layout

- `server.py` — zero-dependency HTTP server (static app, JSON APIs, game-asset
  serving, live designer-queue parsing, and `/api/chat` which shells out to the
  local `claude` CLI with a per-persona system prompt, read-only repo tools).
  A persona's prompt now also carries two things that make chat additive rather
  than amnesiac: their own memory file, and the work already filed to them by
  `work.py` — so "what are you working on?" has a real answer, and something
  filed to Ingrid while the CEO is elsewhere is waiting for her when he arrives.
  - **The intake queue.** When the subscription's 5-hour window runs dry the CLI
    can't answer, and the chat page used to dead-end on "claude CLI failed".
    Now a dry window parks the request in `data/outbox/<id>.json`, the page says
    when tokens come back, and a background thread sends it and holds the reply
    until a browser collects it — so an idea he has at 9pm isn't lost because the
    tokens are. Anything that fails for another reason offers "Queue it for
    later" on the same terms. Delivery never depends on parsing the CLI's reset
    message: the drainer just retries, so a reworded limit can delay an answer
    but can't lose a request. `/api/chat/queue` (GET state, POST enqueue),
    `/api/chat/cancel`, `/api/chat/retry`. Answered items are collectable for
    seven days, which is what lets the laptop pick up what the desktop queued.
- `studio.py` — the art studio's memory of hand edits. Every save from the sprite
  editor lands as a step in that sheet's ledger (see `data/sprite_edits/` below)
  and is filed to the art director as tier-0 work: reading his edit against the
  style guide and writing down what it says about the direction. A hand edit is
  the purest taste signal the project gets — this is what stops it dying as a
  pixel diff in git with the reasoning gone. It deliberately does **not** propose
  style-guide amendments yet; the guide is unsigned (the CEO asked for a look
  session first), so until then this accumulates as the evidence that session
  will be run from.
- `static/` — the single-page frontend. `design.js`/`design.css` are the Design
  Studio tab: the living GDD browsed live from `docs/` via `/api/docs` +
  `/api/doc/<path>` — served from the repo on every request, never copied. The
  index leads with the vision (the one-sentence pitch, a five-phase rail with
  premise/maturity/milestones per phase, and a computed "design frontier" card
  joining the next undone phase milestone to its design debt); every doc is a
  real route (`#/design/doc/<path>[@anchor]`), and rendered docs get heading
  anchors, a contents rail, and live S-/P-/D-/Q- citation links.
- `static/vendor/` — vendored third-party libs, fetched once from jsdelivr so the
  app has no runtime network dependency: `marked` 16.4.1 (MIT, markdown parsing)
  and `DOMPurify` 3.2.7 (Apache-2.0/MPL-2.0, HTML sanitization) for chat replies.
- `work.py` — **how work originates.** Every chat exchange is read afterwards for the
  follow-up it creates, and the follow-up is filed automatically: owner, level, and a tier
  set by how hard the work is to walk back. Tier 0 (nothing to walk back) is carried out
  immediately and the CEO reviews the *result*; tier 1 (repo changes) queues for a build
  session; tier 2 (hard to reverse, or his taste) waits for his yes. Nothing waits on
  permission to *exist*. `docs/HOW_WORK_ORIGINATES.md` is the norm in prose, S-9 in the
  decision log settles it, and `data/work_policy.json` is the copy the server reads — edit
  that to change the norms without touching code. Items live in `data/work/`, the Work page
  in `static/work.js`.
- `drain.py` — **the studio working its own queue.** Tier 1 is "do it, show the
  diff", and the second half of that had no machinery: items were filed, marked
  `waiting_session`, and waited for a human. Twenty-two accumulated. The drain
  runs each one through a worker holding *only* the owning seat's context — its
  org record, its own notes, the card — on that seat's default `model` from
  `org.json`, in its own git worktree, so several seats can be wrong at once
  without standing on each other. The chief of staff then reads the diff against
  the brief; patches that survive land on the working tree one at a time, and
  both suites run once if any of them touched the game. Nothing is committed:
  the item goes back to `for_review` with the diff, the check, the suites and the
  bill, and Daniel approves the result. A worker that finds the item needs *him*
  stops and says what it needs, which is how the queue produces escalations
  rather than swallowing them. `python3 hq/drain.py --list` to see the queue,
  `--all` to drain it. `docs/HOW_WORK_ORIGINATES.md` is the norm in prose.
- `data/org.json` — org chart + personas (Amazon titles/levels).
- `data/entities.json` — entity gallery: sprite-sheet frame rects, fps, sounds,
  code refs. Update when a new species/crop/object ships (the Zoo's roster and
  `systems/species_defs.gd` are the source of truth to mirror). `frames` is the
  pool of cells an entity draws from; the optional `anims` list names its
  animations as ordered index lists into that pool (`{id, label, frames, fps,
  kind}` — `kind: "stills"` marks poses/variants that never cycle). One cell may
  sit in several animations; the editor computes the reverse lookup, so it is
  never stored. No `anims` means one implicit animation: the frame list itself,
  which is how every entity behaved before the field existed. The game code
  being mirrored (e.g. `player/player.gd::_load_sprites`) stays the source of
  truth for what each row and column means.
- `data/projects/*.json` — the program report, one file per project, ordered by
  `priority`.
- `data/decisions/*.json` — curated decision cards for the inbox: plain-language
  question, options with a recommendation, attachments
  (image/audio/sprite/video/look), links. Keep in sync with open items in
  `docs/DESIGNER_QUEUE.md`.
- `data/looks/<scenario>/` — a look sheet delivered to a card (Q-86): the question
  staged in the real game with every draft photographed under identical conditions,
  composed into `sheet.png` (and `motion.png` where the argument is that it moves)
  with a `look.json` describing it. A card asks for one with
  `{"type": "look", "scenario": "<id>"}`; `tools/compose_look_sheets.py` reads the
  cards and copies in exactly the sheets they cite, which is why these are the only
  look captures in git — the rig's own output under `tools/looks/` is gitignored.
- `data/rulings/` — rulings the CEO records in the inbox (`<Q-id>.json`, plus a
  running `RULINGS.md` ledger). `status: pending_integration` means a work session
  still needs to fold it into the design docs — see CLAUDE.md "Docs and process".
- `data/sprite_edits/<sheet>/` — the sprite editor's ledger, written by
  `studio.py`. `0000.png` is the sheet before anyone edited it here; every save
  after that appends `NNNN.png` (the sheet at that step) and `NNNN.json` (what
  changed, and the CEO's own one-line answer to "what were you fixing?"). Nothing
  is ever overwritten, so any step can be inspected or reverted to — and a revert
  is itself a step, so the history only grows. Replaces the old
  `data/sprite_backups/` (one copy per sheet per day, so a second edit the same
  day had no recorded "before" at all); that directory is no longer written to and
  is kept only for the one copy it already holds.
- `data/staff/<person>/memory.md` — what a persona carries between conversations.
  Chat is a fresh read-only CLI session every time, so anything told to Ingrid on
  Tuesday used to be gone by Wednesday. A reply may end with a
  `<remember>...</remember>` block: the server strips it before the CEO sees the
  reply and appends it here, and the tail of the file rides in that person's
  system prompt next time. No extra model call, no write tools.

The `.gdignore` keeps Godot from scanning this directory. The chat feature and
project data are dev-facing; nothing here ships with the game.
