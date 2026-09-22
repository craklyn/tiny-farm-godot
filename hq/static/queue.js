/* Tiny Farm HQ — the queue reader (docs/QUEUE_TO_ZERO.md §6-§7).

   Replaces the Work page at the same addresses. Loaded after work.js as a
   classic script so this file's routes[...] assignment wins the last-write —
   work.js and its renderWork() are untouched and still loaded (another
   session owns that file); this file only overrides where #/work and #/inbox
   point. work.js's verdict endpoints (/api/work/accept, /drop, /approve,
   /respond) and the decision endpoint (/api/ruling) are reused exactly as
   they are — this page is presentation over policy the studio already ruled
   on (S-16, S-17), not a new backend. */
"use strict";

routes["/work"] = renderQueue;
routes["/inbox"] = renderQueue;
if (/^\/(work|inbox)(\/|$)/.test(location.hash.slice(1) || "/")) route();

/* ---------------------------------------------------------------------------
   FIELD INVENTORY — what each part of the anatomy (§6 band/row, §7 pane)
   needs, and whether today's real data (hq/data/work/*.json via /api/work,
   hq/data/decisions/*.json + hq/data/rulings/*.json via /api/queue) already
   carries it. Written once so whoever builds the rest of the pane does not
   have to re-derive it from the mock a second time.

   §6 THE BAND (built below, real data, no server change)
   - count waiting, minutes at his pace, picks vs reads
     -> derived: count of items in the "his" bucket after classify(); pick if
        it carries a recommendation, read if not; 30s/120s each, summed.
   - "before" / "yesterday" comparison
     -> DEFERRED: build_mock.py hard-codes yesterday's raw count (63) because
        it is a one-time snapshot; a live page needs a real day-over-day
        reading (a small history file written once a day) before this line can
        be honest. Left out rather than shown with a fabricated number.

   §6 THE ROW (built below, real data, no server change)
   - one-sentence question      -> work card: title (+ recommend.question when
     set); decision card: title. Real data: present on every card.
   - recommended answer         -> work card: recommend.answer; decision card:
     the option whose label ends "(Recommended)". Real data: present on most
     decisions, present only where a card's owner wrote one for work cards —
     absent cards show "no recommendation yet, <owner> owes one" per §5 rule 2.
   - Yes                        -> POST /api/work/approve or /accept (work),
     POST /api/ruling with the recommended option (decision). Real endpoints,
     unchanged.
   - Talk                       -> POST /api/work/respond (work), POST
     /api/ruling with judgment and no option (decision) — the same "send it
     back with a comment" path decisionCard() already uses. Built here as an
     inline composer under the row; §7's full talk box (with the thirty-second
     hand-back clock, §8) is not built — there is no `owed` state or clock on
     the server yet, only the "already answered, waiting on the studio" signal
     work.js reads from awaiting_reply / decisionCard's waitingOnStudio, which
     this page surfaces in the "Coming back to you" strip instead.
   - cost chip (30s / 2min)     -> §7a (which of three forms, and its exact
     cost) is Daniel's to rule on and has not been (QUEUE_TO_ZERO.md §14). This
     page uses the simple pick/read split the mock uses until that lands.
   - subject grouping           -> NOT PRESENT ON ANY CARD TODAY. §13: subject
     is set by the chief of staff at prepping time; nothing that prepares a
     card writes it yet. Every item falls into "Everything else" until that is
     fixed — filed below rather than left silently inert a second time.

   §6 FOLDS (built below, read-only — no Undo control; see note under Yes)
   - "Landed without you"       -> which cards would clear the landing bar
     (QUEUE_TO_ZERO.md §4) if it exists, computed live by classify() below,
     ported line for line from docs/design/mockups/queue_to_zero/build_mock.py.
     Undo needs a real revert action on a real `landed` state, and neither
     exists server-side yet (§12 row 1, not built) — so these lines are shown
     for what they are, a preview of what the bar would do, with no button
     that would silently do nothing if pressed.
   - "Back with the studio"    -> same classify() call, the "studio" bucket.

   §7 THE PANE — built below (qPaneHtml), same eight-item order §7 lists:
   1. question, card title, owner            — present (work + decision cards)
   2. recommend.{answer,why,instead}         — present where an owner wrote one
   3. decision.options[].{label,detail}      — present on decision cards only
   4. follow_ups[].{title,owner,tier}        — present; tier decides "lands on
      its own" (0-1) vs "would come back as a question" (2), per §5. Rendered
      as an h3 heading ("What yes starts") directly over a real <ul> of real
      <li>s — the 2026-09-21 layout note, after "Accepting files exactly
      this" on the old Work page read as a noun rather than a heading over
      a list.
   5. walk-back sentence                     — DERIVED, not stored (qWalkBack):
      "one git revert" if diff.applied, "nothing, it is a reading" if tier 0,
      else the bucket's reason; a decision always names the ruling rule since
      it is never git-revertable.
   6. conversation                           — work card: conversation[],
      mapped to {who, text, at}; decision card: replies[], same shape. The
      pane's "So far" section is only shown when there is one.
   7. evidence: result, diff.stat, suites, check, ask/brief — foldable
      <details>; a decision card's evidence is its question narrative,
      why_now, and its attachments (rendered with app.js's attachmentEl, so
      an image is a real image here, not a filename in a paragraph)
   8. Yes / No / Talk to <owner>             — No calls /api/work/drop, which
      exists on work cards only; a decision has no equivalent endpoint, so
      the pane omits No there (canDrop on the row) rather than wiring a
      button to nothing

   Kept off this page on purpose (§13, §5 rule 2): raw, unprepped questions
   from DESIGNER_QUEUE.md ("Questions not yet prepped for you") and closed
   history. Neither is his to work through; the old Work page showed both,
   this reader shows neither. */

const Q_PICK_SECONDS = 30, Q_READ_SECONDS = 120;



function qFirst(name) { return String(name || "").split(" ")[0]; }

function qNoRecommendation(row) {
  return row.isDecision
    ? "The studio has not recommended an option yet."
    : `${qFirst(row.owner.name)} has not recommended an answer yet.`;
}

/* Evidence, folded, in the order §7 item 7 lists it: what came back, files
   changed, suites, the checker, the brief. Only what the card actually
   carries — an absent field is left out rather than shown empty. */
function qWorkEvidence(card, ownerName) {
  const items = [];
  if (card.result) items.push({ label: "What came back", text: card.result });
  if (card.diff && card.diff.stat) items.push({ label: "Files changed", text: card.diff.stat });
  if (card.suites && Object.keys(card.suites).length)
    items.push({ label: "Test suites", text: Object.entries(card.suites)
      .map(([name, v]) => `${name}: ${(v && typeof v === "object" ? v.ok : v) ? "green" : "red"}`).join(", ") });
  if (card.check && card.check.summary) items.push({ label: `Checker: ${card.check.verdict || ""}`, text: card.check.summary });
  const brief = card.ask || card.source_message || "";
  if (brief) items.push({ label: `The brief written for ${ownerName}`, text: brief });
  // The session that produced this result is written down as it runs, so the
  // result can be read back to how it was made rather than taken on trust.
  if (card.started || card.diff) {
    items.push({ label: "How it was done", link: `#/chat/bullpen?item=${encodeURIComponent(card.id)}`,
                 text: "Open the record of the session that produced this: every file it read, every change it made, every command it ran, and what it cost." });
  }
  return items;
}

/* The named deliverable is the thing Daniel is deciding about.  It is not
   technical evidence to discover after the recommendation: its recorded link
   belongs directly under the question in the selected review. */
function qDeliverableEvidence(card) {
  return reviewEvidenceLinks(card);
}

function qDecisionEvidence(c) {
  const items = [];
  if (c.question) items.push({ label: "How this started", text: c.question });
  if (c.why_now) items.push({ label: "Why now", text: c.why_now });
  return items;
}

/* What you would be walking back (§7 item 5): one git revert, a reading with
   nothing to undo, or the reason it needed him in the first place. A decision
   is never git-revertable, so it always names the ruling rule instead. */
function qWalkBack(row) {
  if (row.isDecision) return "A ruling can be changed until it is worked in; after that it is one more ruling.";
  if (row.diffApplied) return "One git revert.";
  if (row.tier === 0) return "Nothing to walk back; it is a reading.";
  return `This is the reason it is in front of you: ${row.reason || "hard to walk back, or a matter of taste"}.`;
}

/* What yes starts (§7 item 4): a one-line summary over the real follow-up
   list — not a lead-in sentence a noun can hide inside (2026-09-21 layout
   note). The heading and the <ul> in qPaneHtml are what actually fixes that;
   this only supplies the sentence above them. */
function qYesCauses(row) {
  if (row.isDecision) return "Records your pick; the seat that opened the card works it into the design that day.";
  const fus = row.followUps;
  if (!fus.length) return "It closes. Nothing else starts.";
  const risky = fus.filter(f => (f.tier ?? 1) === 2).length;
  let s = fus.length === 1 ? "One piece of work starts" : `${fus.length} pieces of work start`;
  if (risky) s += `; ${risky} of ${risky === 1 ? "it" : "them"} would come back to you as a question`;
  return s + ".";
}

/* A work card as a question row. Mirrors question_for()/work_item() in
   build_mock.py — now carries everything both the row and the pane (§7)
   need, since a decision and a work card render through one anatomy. */
function qWorkItem(card, org, reason) {
  const owner = ownerOf(org, card.owner);
  const rec = card.recommend || {};
  const hasRec = !!rec.answer;
  const question = rec.question || card.review_question || "Does this reviewed result stand?";
  // A card whose only evidence is a change to the files is not prepped: nobody
  // has said what he should do about it, and pretending otherwise turns his
  // thirty-second pick into a rubber stamp (docs/QUEUE_TO_ZERO.md §7a).
  const answer = hasRec ? rec.answer : "";
  const convo = (card.conversation || []).filter(m => m.text)
    .map(m => ({ who: m.role === "daniel" ? "You" : qFirst(owner.name), text: m.text, at: m.at || "" }));
  return {
    kind: card.state === "needs_approval" ? "approve" : "review",
    id: card.id, cardId: card.id, isDecision: false, subject: card.subject || "",
    title: card.state === "for_review" ? reviewTitle(card) : card.title,
    question, answer, why: rec.why || "", instead: rec.instead || "",
    owner, seconds: answer ? Q_PICK_SECONDS : Q_READ_SECONDS, state: card.state,
    tier: card.tier ?? 2, reason: reason || "hard to walk back, or a matter of taste",
    diffApplied: !!(card.diff && card.diff.applied),
    options: [], followUps: card.follow_ups || [], conversation: convo, attachments: [],
    deliverableEvidence: qDeliverableEvidence(card),
    evidence: qWorkEvidence(card, owner.name), source: `work card ${card.id}`, canDrop: true,
  };
}

/* An open decision card as a question row. Mirrors decision_item(). */
function qDecisionItem(c, org, seats) {
  const opts = c.options || [];
  const clean = l => (l || "").replace(" (Recommended)", "");
  const rec = opts.find(o => (o.label || "").includes("(Recommended)"));
  const seat = (seats && seats.seats || []).find(s => s.id === c.owner);
  const ownerId = seat ? seat.held_by : c.owner;
  const foundOwner = ownerId && ownerOf(org, ownerId);
  const owner = foundOwner && foundOwner.name && foundOwner.name !== ownerId
    ? foundOwner : { name: "the studio", emoji: "🗂️" };
  return {
    kind: "rule", id: c.id, cardId: c.id, isDecision: true, subject: c.subject || "",
    title: c.title, question: c.title,
    answer: rec ? clean(rec.label) : "", why: rec ? (rec.detail || "") : "", instead: "",
    recOption: rec, owner, seconds: rec ? Q_PICK_SECONDS : Q_READ_SECONDS,
    tier: 2, reason: "hard to walk back, or a matter of taste", diffApplied: false,
    options: opts.map(o => ({ key: o.key, label: o.label, detail: o.detail || "",
      recommended: (o.label || "").includes("(Recommended)") })),
    followUps: [],
    conversation: (c.replies || []).map(r => ({ who: r.by === "claude" ? "Adam" : (r.by || "the studio"), text: r.text || "", at: r.at || "" })),
    attachments: c.attachments || [], deliverableEvidence: qDeliverableEvidence(c),
    evidence: qDecisionEvidence(c), source: `decision card ${c.id}`, canDrop: false,
  };
}

async function qLoadData() {
  delete cache["/api/queue"];
  const [org, snap, queue, waiting, seats] = await Promise.all([
    api("/api/org"), fetch("/api/work").then(r => { noteVersion(r); return r.json(); }),
    api("/api/queue"), api("/api/waiting-on-you"), api("/api/seats"),
  ]);
  const ready = new Set((waiting.ready || []).map(row => row.source_id));
  const reasons = new Map((waiting.items || []).map(row => [row.source_id, row.reason]));
  const rulings = queue.rulings || {};
  const curated = queue.curated || [];
  const decided = new Set(queue.decided || []);
  const open = curated.filter(c => !decided.has(c.id) && !c.ruled);
  const answeredBack = c => {
    const r = rulings[c.id];
    if (!r || !r.ruled_at) return false;
    const since = (c.replies || []).some(x => String(x.at || "") > String(r.ruled_at));
    return !since;
  };
  const hisDecisions = open.filter(c => ready.has(c.id));
  const studioDecisions = open.filter(answeredBack);

  const work = snap.items || [];
  const statuses = new Map((waiting.items || []).filter(row => row.source === "work")
    .map(row => [row.source_id, row]));
  const his = [], pending = [], studio = [], wentIn = [], awaitingStudio = [], closed = [];
  work.forEach(card => {
    const row = statuses.get(card.id) || { status: "unknown", reason: "Current work status is unavailable." };
    const entry = { card, reason: row.reason };
    if (row.status === "ready") his.push(entry);
    else if (row.status === "completed") wentIn.push(card);
    else if (row.status === "ready_to_apply") pending.push(entry);
    else if (row.status === "closed") closed.push(entry);
    else {
      studio.push(entry);
      if (row.status === "awaiting_owner_reply") awaitingStudio.push(card);
    }
  });
  wentIn.sort((a, b) => String((b.landed || {}).at || "").localeCompare(String((a.landed || {}).at || "")));
  return { org, rulings, hisWork: his, pendingCompletion: pending, studioWork: studio,
    wentIn, closedWork: closed, hisDecisions, studioDecisions, awaitingStudio, waiting, seats };

}

function qGroupBySubject(rows) {
  const groups = new Map();
  rows.forEach(r => {
    const key = r.subject || "Everything else";
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(r);
  });
  // Groups in the order their first question arrived, except the catch-all,
  // which is always last so a named subject reads before it. Within a group,
  // the quickest question first: several rulings on one subject often settle
  // each other, and the cheap one is the way in.
  const names = [...groups.keys()].sort((a, b) => (a === "Everything else") - (b === "Everything else"));
  return names.map(name => {
    const items = [...groups.get(name)].sort((a, b) => a.seconds - b.seconds);
    return { name, items };
  });
}

function qTimeAgo(tsSeconds) {
  if (!tsSeconds) return "";
  const s = Math.max(0, Math.round(Date.now() / 1000 - tsSeconds));
  return s < 60 ? `${s} s ago` : s < 3600 ? `${Math.round(s / 60)} min ago` : `${Math.round(s / 3600)} h ago`;
}

let qSelected = null;   // id of the row filling the pane, once any exists

/* The side pane (§7): the fixed anatomy, in the order the section numbers it,
   so his eyes learn where each thing lives. A decision card and a work card
   render through this one function from their two field shapes (§6 rule:
   "one reader"). Section 4's heading sits directly over an actual <ul> of
   actual <li>s — the 2026-09-21 layout note, after "Accepting files exactly
   this" on the old Work page read as a noun rather than a heading over a
   list. */
function qPaneHtml(row, org) {
  if (!row) return `<p class="q-pane-empty">Pick a question on the left.</p>`;
  const ownerName = row.owner.name;
  const fuLine = f => {
    const fOwner = ownerOf(org, f.owner).name;
    const tag = (f.tier ?? 1) === 2 ? "would come back as a question" : "lands on its own";
    return `<li>${esc(f.title)} — ${esc(fOwner)} <span class="chip q-chip">${tag}</span></li>`;
  };
  return `
    <div class="q-pane-q">${mdi(row.question)}</div>
    <div class="q-pane-src">${esc(row.title)} · ${esc(row.source)} · ${esc(ownerName)}</div>

    ${row.deliverableEvidence && row.deliverableEvidence.length ? `<div class="q-sec q-review-artifact"><h3>The result to review</h3>${row.deliverableEvidence.map(e =>
      `<a class="plain" href="${esc(e.href)}">${esc(e.label)}</a>`).join(" · ")}</div>` : ""}

    <div class="q-atts" id="q-pane-atts"></div>

    <div class="q-sec"><h3>What I recommend</h3>
      ${row.answer
        ? `<div class="q-rec"><b>${mdi(row.answer)}</b>${row.why ? `<p>${mdi(row.why)}</p>` : ""}${row.instead ? `<p class="q-instead">Instead: ${mdi(row.instead)}</p>` : ""}</div>`
        : `<div class="q-rec q-rec-none"><b>No recommendation on this one.</b><p>${esc(qNoRecommendation(row))}</p></div>`}
    </div>

    ${row.isDecision ? `<div class="q-sec q-decision-form"><h3>Choose an answer</h3>
      <fieldset><legend class="sr-only">Recorded options for ${esc(row.title)}</legend>${row.options.map(o =>
        `<label class="q-choice"><input type="radio" name="q-choice-${esc(row.id)}" value="${esc(o.key)}" data-intent="choose" data-label="${esc(o.label)}">
          <span><b>${esc(o.label)}</b>${o.recommended ? ' <span class="rec">recommended</span>' : ""}<small>${mdi(o.detail)}</small></span></label>`).join("")}
        <label class="q-choice q-revise"><input type="radio" name="q-choice-${esc(row.id)}" value="" data-intent="revise" data-label="None of these — revise and ask me again">
          <span><b>None of these — revise and ask me again.</b><small>Tell the studio what needs to change. The decision stays open.</small></span></label>
      </fieldset>
      <label class="q-talk-l" for="q-decision-feedback">Feedback — optional unless you ask for a revision</label>
      <textarea id="q-decision-feedback" placeholder="Add context for the studio"></textarea>
      <p class="q-decision-status" id="q-decision-status" role="status"></p>
      <button class="q-decision-submit" data-id="${esc(row.id)}">Submit decision</button>
    </div>` : ""}

    <div class="q-sec"><h3>What yes starts</h3>
      <p>${esc(qYesCauses(row))}</p>
      ${row.followUps.length ? `<ul class="q-fu-list">${row.followUps.map(fuLine).join("")}</ul>` : ""}
    </div>

    <div class="q-sec"><h3>What you would be walking back</h3><p>${esc(qWalkBack(row))}</p></div>

    ${row.conversation.length ? `<div class="q-sec"><h3>So far</h3>${row.conversation.map(m =>
      `<div class="q-msg${m.who === "You" ? " q-msg-you" : ""}"><div class="q-msg-who">${esc(m.who)}${m.at ? ` · ${esc(m.at)}` : ""}</div><div>${mdi(m.text)}</div></div>`).join("")}</div>` : ""}

    <div class="q-sec"><h3>The evidence</h3>
      ${row.evidence.length ? row.evidence.map(e =>
        `<details><summary>${esc(e.label)}</summary><div>${mdi(e.text)}${
          e.link ? `<p><a class="plain" href="${e.link}">Open the session in the bullpen</a></p>` : ""}</div></details>`).join("")
        : `<p class="q-pane-muted">Nothing recorded yet.</p>`}
    </div>

    ${row.isDecision ? "" : `<div class="q-talk-box" id="q-pane-talk">
      <label class="q-talk-l" for="q-talk-t">Anything you want to say about this — optional</label>
      <textarea id="q-talk-t" placeholder="A line of why. Whichever button you press, ${esc(qFirst(ownerName))} reads this."></textarea>
      <div class="q-talk-acts">
        <button class="ghost q-send" data-id="${esc(row.id)}">Ask ${esc(qFirst(ownerName))}, without answering yet</button>
        <span class="q-talk-n" id="q-talk-st">${esc(qFirst(ownerName))} answers within thirty seconds or hands it back and you move on.</span>
      </div>
    </div>`}

    ${row.isDecision ? "" : `<div class="q-acts-big">
      ${row.answer
        ? `<button class="q-yes" data-id="${esc(row.id)}">${
            row.isDecision ? `Rule: ${esc(row.answer)}` : "Yes — do what is recommended above"}</button>`
        : (row.isDecision ? ""
          // Nobody wrote a recommendation, which is the studio's failing, not a
          // reason he cannot answer. A finished result always has a yes.
          : `<button class="q-yes" data-id="${esc(row.id)}">Yes — this stands</button>`)}
      ${row.canDrop ? `<button class="ghost q-no" data-id="${esc(row.id)}">${
        row.isDecision ? "None of these" : "No — drop this"}</button>` : ""}
    </div>`}`;
}

function qRender(state) {
  const { org, hisWork, hisDecisions, pendingCompletion, studioWork, wentIn, closedWork, studioDecisions, awaitingStudio } = state;

  const rows = [
    ...hisWork.map(x => qWorkItem(x.card, org, x.reason)),
    ...hisDecisions.map(c => qDecisionItem(c, org, state.seats)),
  ];
  const picks = rows.filter(r => r.answer).length, reads = rows.length - picks;
  const minutes = Math.round(rows.reduce((a, r) => a + r.seconds, 0) / 60);
  const groups = qGroupBySubject(rows);

  // Whatever verdict just fired took its row out of `rows`; picking up the
  // new first row is what makes the pane "advance by itself" (§7) without any
  // extra bookkeeping across the reload.
  if (!qSelected || !rows.some(r => r.id === qSelected)) qSelected = rows[0] ? rows[0].id : null;

  const unavailable = state.waiting.available === false;
  const bandHtml = unavailable
    ? `<b>Queue count unavailable.</b><p>HQ could not read the current queue. Try refreshing; this does not mean no items are waiting.</p>`
    : rows.length
    ? `<b>${rows.length} question${rows.length === 1 ? "" : "s"} · about ${minutes} minute${minutes === 1 ? "" : "s"} at your usual pace</b>
       <p>${picks} ${picks === 1 ? "is a pick" : "are picks"} between prepared options, about 30 seconds each.
       ${reads} need${reads === 1 ? "s" : ""} you to read what came back, about two minutes each.${
         reads ? ` Of those ${reads}, nobody has written a recommendation yet; each says who owes you one, and you can still answer.` : ""}</p>`
    : `<b>Nothing is waiting on you.</b><p>The rest of the studio is working.</p>`;

  const owed = [
    ...awaitingStudio.map(c => ({ who: ownerOf(org, c.owner).name, title: c.title, since: c.asked_ts })),
    ...studioDecisions.map(c => ({ who: "the seat that opened the card", title: c.title, since: Date.parse((state.rulings[c.id] || {}).ruled_at || "") / 1000 || 0 })),
  ];
  const stripHtml = owed.length
    ? `<b>Coming back to you:</b> ` + owed.map(o =>
        `${esc(qFirst(o.who))} on “${esc(o.title.slice(0, 60))}”${o.since ? ` <span class="chip q-chip">${esc(qTimeAgo(o.since))}</span>` : ""}`
      ).join(" · ")
    : "";

  const rowHtml = r => `<div class="q-row${r.id === qSelected ? " q-focus" : ""}" data-id="${esc(r.id)}">
    <div class="q-row-main">
      <div class="q-row-q">${mdi(r.question)}</div>
      ${r.answer
        ? `<div class="q-row-r">Recommended: ${mdi(r.answer)}</div>`
        : `<div class="q-row-r q-row-none">No recommendation yet — ${esc(qNoRecommendation(r))}</div>`}
    </div>
    <div class="q-row-acts">
      ${r.kind === "rule" ? "" : `<button class="q-yes" data-id="${esc(r.id)}">Yes</button>`}
      <button class="ghost q-talk" data-id="${esc(r.id)}" title="Open it and write to its owner">Open</button>
      <span class="chip q-chip">${r.seconds <= Q_PICK_SECONDS ? "30 s" : "2 min"}</span>
    </div>
  </div>`;

  const groupsHtml = groups.map(g => !g.items.length ? "" : `
    <h2 class="q-group-h">${esc(g.name)} <span class="chip q-chip q-count">${g.items.length}</span></h2>
    ${g.items.map(rowHtml).join("")}`).join("");

  const foldRow = (card, reason) => {
    const preparation = (state.waiting.items || []).find(row => row.source_id === card.id);
    const warnings = [reason, preparation && preparation.reason, card.check && card.check.summary].filter(Boolean);
    return `<li><span class="q-fold-t">${esc(card.title)}</span>
      <small class="q-fold-r"> · ${esc([...new Set(warnings)].join(" · "))}</small>
      <a class="plain" href="#/work/${encodeURIComponent(card.id)}">Open result</a></li>`;
  };

  const wentInHtml = wentIn.map(c => `<li><b>${esc(c.title)}</b>
    <small class="q-fold-r"> · ${esc(ownerOf(org, c.owner).name)} · went in ${esc(String((c.landed || {}).at || "").replace("T", " "))}</small>
    <button class="ghost q-undo" data-id="${esc(c.id)}">Undo</button></li>`).join("");
  const digestHtml = pendingCompletion.map(({ card, reason }) =>
    foldRow(card, reason)).join("");
  const backHtml = [
    ...studioWork.map(({ card, reason }) => foldRow(card, reason)),
  ].join("");

  const closedHtml = closedWork.map(({ card, reason }) => foldRow(card, reason)).join("");
  const selectedRow = rows.find(r => r.id === qSelected);

  $view.replaceChildren(h(`
    <h1>🧾 Your queue</h1>
    <div class="q-app" id="q-app">
      <div class="q-list">
        <p class="sub">Questions the studio needs an answer to, one at a time, grouped by what they are
        about. Everything else the studio is doing needs nothing from you and is not on this page.</p>
        <div class="q-band">${bandHtml}</div>
        ${stripHtml ? `<div class="q-strip">${stripHtml}</div>` : ""}
        <div id="q-groups">${groupsHtml || `<p class="muted">${unavailable ? "The current queue could not be verified." : "Nothing is waiting on you."}</p>`}</div>
        <h2 class="q-fold-h">Landed without you <span class="chip q-chip q-count">${wentIn.length}</span></h2>
        <details class="q-fold"><summary>${wentIn.length} piece${wentIn.length === 1 ? "" : "s"} of finished work went in without you</summary>
          <ul class="q-fold-list">${wentInHtml || "<li>Nothing yet.</li>"}</ul></details>
        <h2 class="q-fold-h">Awaiting completion <span class="chip q-chip q-count">${pendingCompletion.length}</span></h2>
        <details class="q-fold"><summary>${pendingCompletion.length} result${pendingCompletion.length === 1 ? "" : "s"} still need completion recorded</summary>
          <ul class="q-fold-list">${digestHtml || "<li>Nothing yet.</li>"}</ul></details>
        <h2 class="q-fold-h">Back with the studio <span class="chip q-chip q-count">${studioWork.length}</span></h2>
        <details class="q-fold"><summary>${studioWork.length} card${studioWork.length === 1 ? "" : "s"} go back to their owner instead of to you</summary>
          <ul class="q-fold-list">${backHtml || "<li>Nothing yet.</li>"}</ul></details>
      <details class="q-fold"><summary>Closed work (${closedWork.length})</summary>
        <ul class="q-fold-list">${closedHtml || "<li>Nothing yet.</li>"}</ul></details>
      </div>
      <div class="q-pane" id="q-pane">${qPaneHtml(selectedRow, org)}</div>
    </div>
  `));

  const findRow = id => rows.find(r => r.id === id);
  const attsBox = () => document.getElementById("q-pane-atts");
  const fillAtts = row => { const box = attsBox(); if (box && row) (row.attachments || [])
    .forEach(a => { try { box.appendChild(attachmentEl(a, null, null)); } catch (e) {} }); };
  fillAtts(selectedRow);

  function qSelect(id) {
    qSelected = id;
    document.querySelectorAll(".q-row").forEach(e => e.classList.toggle("q-focus", e.dataset.id === id));
    document.getElementById("q-pane").innerHTML = qPaneHtml(findRow(id), org);
    fillAtts(findRow(id));
  }

  async function qDoYes(r, comment) {
    const path = r.state === "needs_approval" ? "/api/work/approve" : "/api/work/accept";
    const result = await workPost(path, { id: r.cardId, comment: comment || "" });
    if (result && result.error) throw new Error(result.error);
    qRefresh();
  }

  async function qDoNo(r, comment) {
    await workPost("/api/work/drop", { id: r.cardId, comment: comment || "" });
    qRefresh();
  }

  async function qDoTalk(r, text) {
    const result = await workPost("/api/work/respond", { id: r.cardId, message: text });
    if (result && result.error) throw new Error(result.error);
    qRefresh();
  }

  document.getElementById("q-app").addEventListener("click", ev => {
    const yes = ev.target.closest(".q-yes");
    const no = ev.target.closest(".q-no");
    const talk = ev.target.closest(".q-talk");
    const send = ev.target.closest(".q-send");
    const decisionSubmit = ev.target.closest(".q-decision-submit");
    const row = ev.target.closest(".q-row");
    // Whatever he has written in the pane rides along with the verdict, because
    // he must always be able to say why in the same breath as the answer.
    const reason = () => {
      const box = document.getElementById("q-pane-talk");
      const ta = box && box.querySelector("textarea");
      return ta ? ta.value.trim() : "";
    };
    if (decisionSubmit) {
      const r = findRow(decisionSubmit.dataset.id);
      const selected = document.querySelector(`input[name="q-choice-${decisionSubmit.dataset.id}"]:checked`);
      const feedback = (document.getElementById("q-decision-feedback") || {}).value || "";
      const status = document.getElementById("q-decision-status");
      if (!r || !selected) { if (status) status.textContent = "Choose an option before submitting."; return; }
      if (selected.dataset.intent === "revise" && !feedback.trim()) {
        if (status) status.textContent = "Tell the studio what to revise before submitting.";
        return;
      }
      decisionSubmit.disabled = true;
      if (status) status.textContent = "Recording…";
      fetch("/api/ruling", { method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ id: r.cardId, submission_id: decisionSubmissionId(decisionSubmit, selected.dataset.intent, selected.value, feedback), intent: selected.dataset.intent, option: selected.value,
          option_label: selected.dataset.label, judgment: feedback.trim() })
      }).then(async response => {
        const body = await response.json();
        if (!response.ok || body.error) throw new Error(body.error || `Could not record this (${response.status}).`);
        qRefresh();
      }).catch(error => { decisionSubmit.disabled = false; if (status) status.textContent = error.message; });
      return;
    }
    if (yes) { const r = findRow(yes.dataset.id); if (r) { yes.disabled = true; qDoYes(r, reason()).catch(error => { yes.disabled = false; alert(error.message); }); } return; }
    if (no) { const r = findRow(no.dataset.id); if (r) { no.disabled = true; qDoNo(r, reason()); } return; }
    if (talk) {
      // The box is always open in the pane; this only brings the right card up
      // and puts the cursor in it.
      if (qSelected !== talk.dataset.id) qSelect(talk.dataset.id);
      const box = document.getElementById("q-pane-talk");
      if (box) box.querySelector("textarea").focus();
      return;
    }
    if (send) {
      const st = document.getElementById("q-talk-st");
      if (st) {
        // The thirty seconds he was promised, counted where he is looking. The
        // card itself hands back when the clock runs out; this only shows it.
        let left = 30;
        st.textContent = "Sent. Waiting for an answer… 30 s";
        clearInterval(window.qClock);
        window.qClock = setInterval(() => {
          left -= 1;
          st.textContent = left > 0
            ? `Sent. Waiting for an answer… ${left} s`
            : "This is with the studio now. It comes back to the top of your list with the answer.";
          if (left <= 0) clearInterval(window.qClock);
        }, 1000);
      }
      const r = findRow(send.dataset.id);
      const box = document.getElementById("q-pane-talk");
      const text = box.querySelector("textarea").value.trim();
      if (!text || !r) return;
      send.disabled = true;
      qDoTalk(r, text).catch(error => { send.disabled = false; alert(error.message); });
      return;
    }
    const undo = ev.target.closest(".q-undo");
    if (undo) {
      undo.disabled = true;
      undo.textContent = "Putting it back…";
      workPost("/api/work/undo", { id: undo.dataset.id })
        .then(got => { if (got && got.ok === false) undo.textContent = got.why || "Could not undo"; else qRefresh(); })
        .catch(() => { undo.textContent = "Could not undo"; });
      return;
    }
    if (row) { qSelect(row.dataset.id); return; }
  });

  function qRefresh() {
    qLoadData().then(qRender).catch(() => {});
  }

  updateQueueBadge(state.waiting);
}

/* j/k move the selection (and the pane with it); y takes the selected row's
   recommendation; t opens its Talk box. Clicking the row itself (not a
   button) is what qSelect hangs off inside qRender, so a key press just
   dispatches a real click at the row or its button rather than duplicating
   that logic here. Installed once at module scope — wiring it up again
   inside qRender on every poll and every Yes/Talk would stack a new
   document-level listener each time, so a single "y" press would end up
   accepting the same row several times over. */
document.addEventListener("keydown", ev => {
  const here = location.hash.slice(1) || "/";
  if (!here.startsWith("/work") && !here.startsWith("/inbox")) return;
  if (ev.target.tagName === "TEXTAREA" || ev.target.tagName === "INPUT") return;
  const els = [...document.querySelectorAll(".q-row")];
  if (!els.length) return;
  let idx = els.findIndex(e => e.dataset.id === qSelected);
  if (ev.key === "j") { idx = Math.min(els.length - 1, idx + 1); els[idx].click(); }
  else if (ev.key === "k") { idx = Math.max(0, idx - 1); els[idx].click(); }
  else if (ev.key === "y") { if (idx >= 0) els[idx].querySelector(".q-yes")?.click(); return; }
  else if (ev.key === "t") { if (idx >= 0) els[idx].querySelector(".q-talk")?.click(); return; }
  else return;
  els[idx].scrollIntoView({ block: "nearest" });
});

async function renderQueue() {
  const state = await qLoadData();
  qRender(state);
}
