# 10 — Audio Direction

*Status: skeleton — the least-developed axis of the project (nothing exists beyond
`systems/audio_manager.gd` scaffolding). First deliverable: a one-page direction note
(Q-13: Claude drafts, Designer steers taste).*

## Direction questions (Q-13)
1. **Musical identity** — chiptune-adjacent to match P-6's pixel lane, or warmer
   acoustic-cozy (Stardew's lesson: warm beats bleepy for farming)? The delegation arc
   suggests an evolving score: sparse and handmade in phase 1, gaining mechanical layers
   as automation grows, martial by phase 5.
2. **Adaptive layers** — raid tension (a forming trail could *sound* before it's seen —
   audio as the first pest telegraph, which also foreshadows the audio-detection unlock);
   overnight training gets its own "dream" soundscape (D-4 surface layer).
3. **SFX priorities** — action juice for the kid layer first (S-7: satisfying
   plant/water/harvest sounds are half the phase-1 game-feel); every Action verb gets a
   sound identity (S-3 makes the SFX table enumerable from the verb list).
4. **Soundscape comfort** — long-session listenability; a 4-year-old's tolerance and a
   parent's (music that adults in the room don't grow to hate is a real requirement).

## Sections to fill (after direction note approved)
- Music: track list per phase, adaptive layer spec.
- SFX: the verb→sound table; pest/scent audio cues; UI sounds.
- Sourcing: licensed packs vs. commissioned vs. generated; budget `[Designer]`.

## Constraints from decisions
Audio events are (or will be) sim events (S-5) — the same event stream that feeds bot
audio detection (P-7) feeds the mixer: one source of truth for "what made a sound."

---

## Direction proposal v1 (Q-13 draft — Claude, 2026-08-18; awaiting designer taste pass)

**Identity: warm acoustic-toy, not chiptune.** Marimba, kalimba, soft nylon guitar,
hand percussion, hummable and lo-fi. Rationale: cozy farming reads *warm* (Stardew's
lesson), a 4-year-old lives in this soundscape happily, and a parent in the room must
survive 100 hours of it. Pixel art does not obligate bleeps.

**The delegation arc, scored.** One farm leitmotif, reharmonized per phase; the
instrument palette grows with the delegation arc:
- Phase 1 — purely handmade timbres (hands in the dirt).
- Phase 2 — a gentle clockwork/tick layer joins when machines run.
- Phase 3 — low pulses and drums rise during sieges; scent-trail activity gets a dry
  rustling layer *before* raids are visible (audio as the first telegraph — quietly
  foreshadowing the audio-detection unlock).
- Phase 4 — soft synth arpeggios as the "mind" timbre; the overnight training montage
  gets its own dream soundscape (pairs with D-4's dream-replay surface).
- Phase 5 — full hybrid, martial but still built on the farm motif: you brought the
  farm with you.

**SFX: verb-driven foley.** S-3 makes the SFX table enumerable — every Action verb
gets one distinct, satisfying sound. Starter table for current verbs: till (soft
*chunk*), plant (pat-pat), water (sprinkle), harvest (pop + chime), clear_weed (rip),
clear_log (chop), clear_rock (crack), collect (cluckish pop), sell (coin purse),
sleep (yawn + night fade), buy_seed (paper rustle + coin). Crow: squawk + wing flaps;
chicken: cluck family. UI: one soft tick, one soft confirm — nothing else.

**The sound belongs to the verb, not to the tapper** (`[Designer]` ruling, 2026-09-02).
S-3's table is enumerable from the verb list precisely because a verb is one thing
whoever performs it — so a pour heard when the player waters is also heard when the cold
open's neighbour waters, when a replay re-applies that water, and when a phase-4 bot does
the chore for her. Stated as the rule the designer gave it: **an action in the player's
focus gets the same treatment of visualization and sound whoever performs it.** Silence
for a non-player actor is a bug, not a scope line.

Implemented 2026-09-02, reported from play (the neighbour watered in silence): every
cue — the verb's sound, its particles, and any tile mark it leaves — moved out of the
player's node into the one place every resolved Action passes through
(`world/farm.gd:ACTOR_VERB_CUES`), filled from `player/player.gd`'s own answers verb for
verb, with the player filtered out so her cues are not played twice. A tree cleared by
anybody still chops three times, because Q-50's beats are part of the cue.

**The limit is the player's attention, not the actor's nature.** Work done in bulk or
off-screen does not get the per-action treatment: a sprinkler waters nine tiles inside a
single day turn and answers with one spray animation rather than nine simultaneous pours
(those Actions resolve inside `SimWorld.advance_day` and never reach the cue table), and
a farm nobody is playing — the title screen's attract backdrop — stays muted.

**Open gap: `plant` has no foley at all** — nothing in the mixer and no entry in the cue
table. Under the 2026-09-02 rule above that a verb sounds the same whoever performs it,
that silence is everybody's: the cold open's neighbour, a replay re-applying the action,
and a future phase-4 bot all plant as silently as the player does. Parity reached by
nobody being heard is not parity worth having.

Several rows of the starter table above are unfinished — `sell`, `sleep` and `buy_seed`
have no cue either, and the three clears currently reuse the till *chunk* instead of the
rip, chop and crack the table promises. `plant` is the one to fix first: it is the verb
the player performs most, so it is the largest amount of silence in the game.

What the sound needs to do: a pat-pat, soft and low — soil closing over a seed. It should
read as tucking something in, not as an achievement. Harvest already owns the payoff
sound (pop + chime); `plant` must not borrow any of that — no rising pitch, no chime, no
reward sting — or a planted seed will sound like a finished crop.

Sourcing it is Dmitri's: find or record a couple of soft, low pats and pick the one that
reads as closing rather than landing.

**Kid constraints (S-7 spirit):** no harsh stingers; failure/refusal sounds are
comedic (a wet *bonk*, a shrug-like slide whistle at most); gentle attack envelopes;
the whole mix listenable at quiet-household volume.

**Sourcing strawman:** v1 ships on curated CC0/CC-BY packs (tracked in a CREDITS
file); commission 2–3 bespoke loops once the motif is chosen. Bus layout from day 1:
`music / sfx / ambient` via the existing AudioManager.

**Open taste questions for the designer:** (a) acoustic-warm vs. chiptune-leaning —
confirm the premise; (b) melodic motif: do you want to pick/hum one, or should I
propose three candidates at implementation time; (c) how musical should raids get
(full track switch vs. layers over the farm theme)?
