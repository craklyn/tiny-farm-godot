# Phase 1 — The Homestead

*Status: **macro drafted 2026-09-01** (designer rulings Q-79/Q-80/Q-81 folded in; every
number `[Playtest]` unless marked ruled). This is the phase's design doc: experience
goals, the macro chart, beat details, triggers, economy, content budget, telemetry.
Format follows the macro-chart practice (Cerny method): one table the whole phase can be
read from, with prose only where a beat needs argument.*

**Premise:** Manual farming à la Harvest Moon/Stardew: clear the yard, till, plant,
water, harvest, ship, sleep. Individual pests escalate from one thief to three fronts;
the player answers with their own feet and hands until the final beat hands one job — 
crow-scaring — to the first static defender. The player learns the movement/interaction
language of the whole game here.

**Boundary (Q-79 ruled 2026-09-01):** the five-phase structure stands. Phase 1 is the
manual act only; sprinklers, group pests, and livestock-at-scale are phase 2
(`phase-2-first-machines.md`). Phase 1 ends at **the scarecrow** — ruled Q-81: the
scarecrow *is* the first tower, "a non-mobile, small-area tower that only affects one
animal." The tower ladder is thereby continuous across the whole game: scarecrow (1) →
statics and machines (2) → true towers (3) → bots that retire towers (4, D-7).

**Hard constraints:** S-7 (playable by a 4-year-old, touch-first, no reading in the core
loop, no destructive fail states); saturation reads as abundance, never deficit (Q-32);
tap-to-command is the interaction language (S-3, S-6).

---

## 1. Player experience goals

1. **"I know how to live here."** By the end, the verb chain, the economy loop, and the
   day rhythm are second nature — this phase is the teaching act (`design/13`).
2. **"The farm is mine because I made it."** Every cleared tile was a decision; land is
   the visible record of effort (the parcel ladder).
3. **"I am the only thing between the crops and the mouths."** Vigilance is felt bodily
   — the player's own position is phase 1's entire defense system.
4. **"…and now something watches with me."** The finale: relief, pride, and the game's
   thesis whispered once at toy scale — you delegated a job, and it held.

## 2. The macro chart

Target first-run length: **2–3 hours** (Q-21 partial, ruled 2026-09-01). At current
day-lengths that is roughly 25–35 in-game days for a leisurely first run; beats below
carry day *ranges*, but every exit is a sim-measured proof, never a calendar.

| Beat | Days (≈) | New content / mechanic | Rising friction | The manual answer | Exit signal (sim-measured) |
|---|---|---|---|---|---|
| **A — Wake** *(built)* | 1–3 | the verb chain, cause & effect, coins, the egg | none — teaching | — | first bought seed in the ground (`design/13` §4) |
| **B — Meadow** *(built)* | 3–8 | weeds parcel; the crow turns thief | tending vs. guarding splits attention | walk at the crow (discovered, never taught) | N crops shipped ∧ M crows scared by hand |
| **C — Wood** | 8–15 | axe parcel: logs, trees, acorns; **rabbit** debuts; songbird ambient | watering rounds lengthen; two pest fronts | swipe-chain routing; presence spooks the rabbit | wood worked ∧ rabbit spooked K times |
| **D — Quarry** | 15–22 | pickaxe parcel: rocks; **mole** debuts (steals seed) | three fronts; peak triage — the day is spent running | stand guard on the seedbed; stomp the surfacing window | crop-losses-while-elsewhere accumulate (the scarecrow's trigger) |
| **E — Scarecrow** | 22–28 | the **first tower**: static, small radius, crows only | none — this beat is relief | siting it over the crow-hot ground | a crow flees the scarecrow **while the player is elsewhere** → phase gate |

Intensity shape: tending load climbs B→D and stays high (phase 2 relieves it, not
phase 1 — the sprinkler must arrive already-wanted). Vigilance load climbs B→D and
*drops* at E. Ending on the vigilance drop, not the tending drop, is deliberate: the
phase closes on its defense story, and the labor story is the cliffhanger.

## 3. Beat details

**A — Wake** (days 1–3, built): the vignette (`design/13` §4): harvest → plant → water
→ sleep, the grown tile as proof of cause, eggs, sell/buy/refill. No friction by
design. Q-76 ruled: no skip button — beats complete as fast as they are performed.

**B — Meadow** (built): the crow escalates from comedy to cost (T-15/T-20 daily-loss
identity). Scaring by walking is discovered, never taught (`design/13` item 17). The
player's first taste of the phase's core tension: every minute guarding is a minute not
farming — and under Q-32, that must feel like *two good options*, not falling behind.

**C — Wood**: the axe opens logs and standing trees. The **rabbit** (built, unspawned —
`species_defs`) debuts as the second front: no verb answers it, only presence. The
songbird drifts through as pure inhabitance. The watering-round friction that phase 2
will relieve starts genuinely pinching here; it is *not* relieved in this phase
(`design/01`: never optimise away a chore a later phase retires — keep it pleasant).

**D — Quarry**: the pickaxe opens rocks. The **mole** (built, unspawned) debuts: it
steals the seed the player *paid for*, the phase's sharpest loss, and its counterplay is
positional (stand in the seedbed; stomp only in the surfacing window — Q-64's visible
mound). Three fronts now exceed one pair of feet — the phase's designed saturation
point, and precisely the ache the scarecrow answers.

**E — Scarecrow**: see §4.

Not in phase 1: ants and the scent layer, kangaroo, worm (parked, Q-65), sprinkler,
barn livestock — all phase 2+. The chicken is phase 1's whole livestock presence.

## 4. The finale: the scarecrow is the first tower (Q-81)

Ruled 2026-09-01, in the designer's words: *"a non-mobile, small-area tower that only
affects one animal is an okay starting point."* Consequences taken on:

- **Mechanically** it is the sprinkler's sibling: a species row and a brain, static, its
  one behavior a standing `spook_radius` — the same field the player's own body already
  projects. It scares **crows only**, in a **small radius** `[Playtest]`, no
  habituation in phase 1 (habituation/moving-it-around is phase-2 statics depth).
- **The delegation must be witnessed.** The beat only lands if the player *sees* a crow
  veer off while they are busy elsewhere. Presentation owes a noticing aid (the crow's
  flee is already animated; whether it needs more is `[Playtest]`).
- **Acquisition** `[Designer, Q-82]`: bought at the seed box (economy sink, teaches
  nothing new) vs. built from the wood parcel's logs (gives the axe chapter a payoff and
  foreshadows crafting). Straw-man: built from logs — the first thing the yard's
  materials *become*.
- **Trigger**: offered only after the sim has measured both mastery and pain — ≥M crows
  scared by hand ∧ ≥L crops lost to crows while the player was elsewhere `[Playtest]`.
  Arriving before the loss is felt would violate the Q-32 relief rule.
- **Gate proof**: the existing 1→2 proof (`SimWorld._phase1_proof_met`: opened parcels
  cleared + first shipments + crows scared) gains a proposed final term: *a crow scared
  by something that is not the player*. The celebration is the proof: the scarecrow
  working alone **is** the kid-legible milestone moment (`design/12` presentation
  column). Code change flagged for M3 planning.

## 5. Pacing: three speeds from one mechanism

Every unlock trigger is a saturation predicate the sim measures, never a day count:

- **Leisurely** — unfinished work costs nothing (Q-32); the next friction waits.
- **Slow** — a player who doesn't see the answer just keeps getting the manual chapter,
  indefinitely playable; the push itself teaches the tool.
- **Fast** — a repeat player *drives* the predicates (plant wide, let the crow feed,
  scare it on sight). Speed is knowledge — the right currency for the teaching act.
  Repeat-run target: **30–45 minutes** `[Playtest]`.

## 6. Economy budget (rough; spreadsheet due at M3 planning, `design/02` §5)

| Beat | Main sink | Rough sizing rule |
|---|---|---|
| A–B | seeds | the T-11 loop: one crop funds three seeds |
| C–D | seeds at scale; can-refills are time, not gold | surplus accumulates — the phase has no mid-phase money wall |
| E | the scarecrow | ≈ a few days of shipping surplus if bought; ≈ a wood-parcel session if built (Q-82) |

The phase deliberately ends money-easy: phase 2's machines are the first real sinks.

## 7. Content inventory (build cost of this doc)

| Item | Status |
|---|---|
| Beats A–B, parcels, tools, economy objects, crow, chicken | ✅ built (M1.5/M2.5) |
| Rabbit, mole, songbird | ✅ built, need spawn-in + tuning (content sequencing) |
| Scarecrow | new: species row + brain (sprinkler pattern), art (one sprite, retro-diffusion pipeline), acquisition path (Q-82), trigger + proof term |
| Beat-C/D trigger predicates | new, sim-side, testable headless |

No new engine capability is required; the phase completes on the actor system as built.

## 8. Telemetry & playtest plan

The session trace already records every action and dead tap. Per-beat measures to add or
watch: time-to-first-sale (A); crows scared by hand and crops lost per day (B–D);
watering actions per day (the phase-2 handoff number); time between scarecrow-available
and scarecrow-placed (did the offer read?); time between placement and the witnessed
scare (did the payoff land?); first-run wall-clock to gate vs. the 2–3 h target.
Existing bar: the M1.5-style fresh-adult session remains the evidence standard.

## 9. Risks

1. **The finale underwhelms** — one small static scaring one bird may read as a shrug,
   not a thesis. Mitigation: the witnessed-scare presentation beat; the gate celebration
   rides on it. `[Playtest]`
2. **Beat D overshoots** — three fronts at once may tip abundance into stress for the
   young end of S-7. Mitigation: front counts are per-species spawn scheduling, all
   sim-tunable; kid-mode dial exists (P-2).
3. **2–3 h is tight** for five beats — if playtests run long, beats C and D compress
   (the parcels can shrink) before any beat is cut.

## 10. Open items

- **Q-82 (Designer)** scarecrow acquisition: bought vs. built-from-logs (straw-man: built).
- Proof-term change (§4) lands with M3 planning.
- All `[Playtest]` numbers above; first pass at M3's fresh-adult session.
