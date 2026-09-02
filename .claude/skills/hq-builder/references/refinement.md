# Phase 4 — The refinement loop

The blueprint produces a dashboard; iteration produces the one the leader
lives in. The loop is simple — the leader uses it, complains, and each
complaint becomes a rule applied everywhere — but it needs an organizing
principle to keep the fixes from being local patches.

## The organizing principle

**The leader's attention is the scarcest resource in the system.** Every
refinement question reduces to: does this pixel earn its share of that
attention? Concrete consequences that fell out of applying it:

- **One hero card** for the single thing only the leader can do right now.
  Everything else is a dense ranked list below it.
- **Badges mark exceptions only.** In a list that is by definition "for
  you", a FOR YOU pill carries zero bits. Keep FIRE / WATCH / FYI; let
  plain actions go bare.
- **Dedupe by unblocking action, not topic.** If one act (a playtest
  session, one ruling) unblocks three projects, that's *one* queue item
  listing its beneficiaries — not three echoes. This requires projects to
  declare `blocked_on` and a named `unblock_action`.
- **Status at a glance from everywhere.** Nav entries carry live status
  marks so the sidebar doubles as an always-visible status board; anything
  at fire/attention pins itself visible and never folds, with the reason in
  the tooltip. Collapsing is only for quiet things.
- **References resolve.** No "the milestone" prose that assumes context:
  every referenced item renders as a row with link, owner, priority, and
  blocked-age. The leader must never need the author's memory to act.

## Every row answers the leader's four questions

For program/status rows, the leader's job is orient → anticipate → detect
drift → act. So each row shows:

1. **NEXT** — the first undone plan step, so the row reads as an
   expectation, not just a status. Steps naming the leader self-identify
   the ones waiting on *them*.
2. **Last moved** — derived from git's last touch of the project file, so
   drift shows without anyone maintaining a date.
3. **Stuck on** — a resolvable chip linking the blocking decision or the
   project carrying the unblocking action.
4. **Who to chase** — the owner as one-click delegation: open their chat
   with the status question pre-drafted. Chasing costs a click, not a
   context rebuild.

Persist the leader's chosen view (axis, filters) — they form habitual views,
and losing them costs orientation time on every visit.

## The passes to schedule deliberately

- **An adversarial review, once the surface matters.** Commission a
  skeptical full review (fresh agent, instructed to find lies and races)
  and fix every confirmed finding. Expect the worst class to be *unearned
  greens* — e.g. a verdict regex matching a failure line's own wording, so
  a regression shows green. In a trust product, showing green during a
  failure is the defining bug.
- **A visual-language pass.** An HQ usually inherits its theme from the
  project; at some point derive one deliberately: status drawn with CSS
  (never emoji) on data surfaces, a minimum readable type size, tabular
  numerals for numbers, and **borrowed glyph vocabulary** — green check /
  amber ! / red x / gray dash, the grammar GitHub and CI tools already
  taught everyone. Color stays redundant with the glyph, so the scheme is
  colorblind-safe by construction. An invented shape vocabulary, however
  tidy, has to be learned — borrowed vocabulary is intuitive on first sight.
- **Grow axes, not length.** When a page accumulates, add another way to
  slice it (release trains / by priority / by pillar / blocked-by-age)
  rather than lengthening the default view.

## Working the feedback

- **Adopt load-bearing sentences verbatim as rules.** When the leader says
  "my job is to unblock my org", that's not a comment on one widget — it's
  a design rule. Re-derive the affected surfaces from it and quote it in
  the commit/doc so it keeps governing.
- **Fix the deeper redundancy behind the surface complaint.** "These two
  labels mean the same thing" is often a data-model gap (nothing declared
  what unblocks what) wearing a UI costume. Patch the model, and the UI
  fix falls out.
- **Verify by observed behavior.** A collapse that toggles a `hidden`
  attribute the CSS outranks looks fixed in the diff and does nothing on
  screen. Confirm with computed styles / real responses / real pixels
  before reporting done.
- **Give the design function an owner.** It's surprisingly effective to
  "hire" a designer persona into the org chart with a mandate and charter.
  Design rules accumulate somewhere durable, the leader can chat with the
  role, and the org chart stays an honest map of how the HQ is actually
  run. The same goes for a TPM persona owning the program report (release
  trains, critical sets, cut lines) and a chief of staff owning the brief.
- **Small honest details compound.** No-cache headers, escaped
  artifact-sourced strings, a badge that counts only what's truly for the
  leader, stale labels with poll times — trust in the whole surface is the
  sum of these.
