#!/usr/bin/env python3
"""Fixtures for the one ready-for-Daniel projection."""
import os
import json
import tempfile
import subprocess
from pathlib import Path
from unittest.mock import patch
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

import server  # noqa: E402


REC = {"question": "Keep it?", "answer": "Keep it", "why": "It works",
       "instead": "Send it back"}


def card(card_id, state, **extra):
    out = {
        "id": card_id,
        "state": state,
        "recommend": REC,
        "deliverable": {
            "name": "The revised result",
            "evidence": [{"label": "Review it", "href": "/review/result"}],
        },
        "follow_ups": [],
    }
    out.update(extra)
    if out.get("follow_ups") is None:
        out.pop("follow_ups")
    return out


def main():
    failures = []

    def check(value, label):
        print(("ok   " if value else "FAIL ") + label)
        if not value:
            failures.append(label)

    decisions = [
        {"id": "q-ready", "title": "Ready", "options": []},
        {"id": "q-returned", "title": "Returned", "options": [],
         "replies": [{"at": "2026-09-21T12:01:00Z"}]},
        {"id": "q-studio", "title": "With studio", "options": []},
        {"id": "q-done", "title": "Done", "options": []},
    ]
    queue = {"curated": decisions, "decided": ["q-done"], "rulings": {
        "q-returned": {"judgment": "More detail", "ruled_at": "2026-09-21T12:00:00Z"},
        "q-studio": {"judgment": "More detail", "ruled_at": "2026-09-21T12:00:00Z"},
        "q-done": {"option": "b", "status": "pending_integration"},
    }}
    fixtures = [
        card("w-ready", "for_review"),
        card("w-approval", "needs_approval"),
        card("w-unprepared", "for_review", recommend={}),
        card("w-no-question", "for_review", recommend={}, recommendation_required=False,
             recommendation_reason="Daniel must judge the result."),
        card("w-no-recommendation", "for_review", recommend={"question": "Keep it?"}),
        card("w-no-recommendation-explanation", "for_review", recommend={},
             review_question="Keep it?", recommendation_required=False),
        card("w-no-deliverable", "for_review", deliverable={}),
        card("w-no-evidence", "for_review", deliverable={"name": "The revised result"}),
        card("w-no-consequences", "for_review", follow_ups=None),
        card("w-explicit-verdict", "for_review", recommend={},
             review_question="Does this finished result stand?",
             recommendation_required=False,
             recommendation_reason="Only Daniel can judge whether this animation reads clearly."),
        card("w-reply", "for_review", awaiting_reply=True),
        card("w-held", "for_review", held_patch="/tmp/patch"),
        card("w-studio-held", "for_review", tier=1,
             diff={"applied": False, "why_not": "overlaps uncommitted files"},
             workflow_view={"blocker": {"type": "code_conflict",
                                         "reason": "The candidate overlaps uncommitted files."}}),
        card("w-preparing", "prepping"),
        card("w-doing", "doing", started="2026-09-21T12:00:00Z"),
        card("w-waiting", "doing", started=""),
        card("w-scheduled", "waiting_session"),
        card("w-build-running", "waiting_session", started="2026-09-21T12:00:00Z"),
        card("w-accepted", "accepted"),
        card("w-landed", "landed", suites={"unit": {"ok": True}}),
        card("w-reading", "for_review", tier=0, recommend={}),
        card("w-green", "for_review", tier=1, recommend={}, suites={"unit": {"ok": True}}),
        card("w-failed", "for_review", tier=0, recommend={}, check={"verdict": "fail"}),
        card("w-risky", "for_review", tier=0, recommend={}, follow_ups=[{"tier": 2}]),
        card("w-old", "for_review", tier=0, recommend={}, source="chief-of-staff", created="2026-09-10"),
        card("w-unknown", "unrecognized"),
    ]
    old_queue, old_items, old_held = server.api_queue, server.work.items, server.work._held_back
    server.api_queue = lambda **kwargs: queue
    server.work.items = lambda **kwargs: fixtures
    server.work._held_back = lambda item: item["id"] in ("w-held", "w-studio-held")
    try:
        got = server.waiting_on_you()
        ids = {row["source_id"] for row in got["ready"]}
        check(ids == {"q-ready", "q-returned", "w-ready", "w-approval", "w-explicit-verdict"},
              "prepared decisions, returned decisions, reviews, approvals and explicit verdicts share one ready set")
        check(got["count"] == 5 and got["counts"] == {"total": 5, "work": 3, "decisions": 2},
              "the total and its split are derived from that set")
        reading = server.waiting_reading()
        dashboard = server.waiting_block()
        check(reading["count"] == dashboard["count"] == len(ids),
              "dashboard and navigation totals match the ready IDs shown by the queue")
        states = {row["source_id"]: row["status"] for row in got["items"]}
        preparation = {row["source_id"]: row.get("preparation") for row in got["items"]}
        for card_id, code in (("w-no-question", "question"),
                              ("w-no-recommendation", "recommendation"),
                              ("w-no-recommendation-explanation", "recommendation_explanation")):
            check(preparation[card_id]["missing"] == [code] and card_id not in ids,
                  f"{code} has its own preparation gap and cannot enter the ready queue")
        check(preparation["w-no-deliverable"]["missing"] == ["deliverable", "evidence"],
              "a work card without its named deliverable stays out of the ready queue")
        check(preparation["w-no-evidence"]["missing"] == ["evidence"],
              "a named deliverable needs inspectable evidence")
        check(preparation["w-no-consequences"]["missing"] == ["consequences"],
              "a review records what Daniel's answer does next")
        check(preparation["w-explicit-verdict"]["ready"],
              "a finished result can ask for an informed verdict without a fabricated recommendation")
        check(states["q-studio"] == "awaiting_owner_reply" and states["w-reply"] == "awaiting_owner_reply",
              "send-backs stay with the studio until an owner returns them")
        check(states["q-done"] == "pending_integration",
              "a chosen ruling remains visibly with the studio until integration")
        check(states["w-held"] == "verification_pending", "held patches await verification")
        check(states["w-preparing"] == "preparing" and
              states["w-doing"] == states["w-build-running"] == "verification_pending",
              "a recorded start without a live session needs studio recovery, not Daniel")
        check(states["w-waiting"] == states["w-scheduled"] == "scheduled"
              and states["w-accepted"] == "closed",
              "unstarted work is scheduled; acceptance is recorded separately")
        check(states["w-reading"] == states["w-green"] == "verification_pending", "legacy readings and green changes need explicit completion verification")
        check(states["w-failed"] == states["w-old"] == "verification_pending", "failed checks and old completion claims need verification")
        check(states["w-risky"] == "preparing" and states["w-unknown"] == "unknown", "risky follow-ups and unknown states cannot imply completion")
        check(states["w-landed"] == "completed", "green tests do not replace recorded landing")

        before = repr((queue, fixtures))
        server.waiting_on_you()
        check(repr((queue, fixtures)) == before, "reading the projection changes no records")

        static = os.path.join(os.path.dirname(HERE), "static")
        with open(os.path.join(static, "app.js"), encoding="utf-8") as f:
            app_js = f.read()
        with open(os.path.join(static, "queue.js"), encoding="utf-8") as f:
            queue_js = f.read()
        with open(os.path.join(static, "work.js"), encoding="utf-8") as f:
            work_js = f.read()
        with open(os.path.join(static, "queue.js"), encoding="utf-8") as f:
            review_queue_js = f.read()
        check("/api/waiting-on-you" in app_js and "/api/waiting-on-you" in queue_js
              and "/api/waiting-on-you" in work_js,
              "navigation and both queue readers consume the shared API")
        check("function reviewTitle(item)" in app_js and "reviewTitle(it)" in work_js
              and "reviewTitle(card)" in review_queue_js,
              "both review views use one deliverable-first title rule with a legacy fallback")
        check('status === "pending_integration"' in review_queue_js
              and "...studioDecisions.map(card =>" in review_queue_js
              and "belong to the studio now, not to you" in review_queue_js,
              "the current Work page keeps pending rulings visible as studio-owned")

        # Execute the production renderers with representative cards.  These
        # checks deliberately assert the order a person reads, rather than
        # merely checking that implementation words occur in a source file.
        renderer_test = r'''
const assert = require("node:assert/strict"), fs = require("node:fs"), vm = require("node:vm");
const root = process.argv[1];
const shared = { routes: {}, location: { hash: "#/" }, route() {}, cache: {},
  api: async () => ({}), fetch: async () => ({ json: async () => ({}) }), noteVersion() {},
  updateQueueBadge() {}, esc: String, mdi: String, md: String,
  reviewTitle: item => "Review: " + ((item.deliverable || {}).name || item.title || "Finished work"),
  ownerOf: () => ({ name: "Rin", emoji: "🌱" }), openSet: () => new Set(), resuming: () => false,
  heldReason: () => "", wantsLine: () => "", tierChip: () => "", againLine: () => "",
  amendNote: () => "", drainBlock: () => "", costLine: () => "", convoBlock: () => "",
  childrenNote: () => "", spawnedNote: () => "", consequence: () => "", replyBox: () => "",
  decisionFor: () => null, setInterval: () => 1, clearInterval() {}, setTimeout() {},
  window: { addEventListener() {} }, localStorage: { getItem: () => null, setItem() {} },
  document: { getElementById: () => ({ addEventListener() {} }), addEventListener() {} }, $view: { replaceChildren() {} },
  h: html => ({ firstElementChild: { html, querySelector: () => null } }), };
const appSource = fs.readFileSync(root + "/hq/static/app.js", "utf8");
const evidenceHelper = appSource.slice(appSource.indexOf("function reviewEvidenceLinks("), appSource.indexOf("/* Markdown for authored prose"));
const evidenceContext = vm.createContext({});
vm.runInContext(evidenceHelper, evidenceContext);
shared.reviewEvidenceLinks = evidenceContext.reviewEvidenceLinks;
const queue = vm.createContext({ ...shared });
const reviewSource = fs.readFileSync(root + "/hq/static/review_evidence.js", "utf8");
vm.runInContext(reviewSource, queue);
vm.runInContext(fs.readFileSync(root + "/hq/static/queue.js", "utf8"), queue);
const index = (text, needle) => { const found = text.indexOf(needle); assert.ok(found >= 0, needle); return found; };
const animation = queue.qPaneHtml({ id: "animation", kind: "review", question: "Does the motion read clearly?", title: "Review: Watering animation", source: "work card animation", owner: { name: "Ingrid" }, answer: "Keep this timing", why: "The pause reads at game size.", instead: "Slow it down", options: [], followUps: [], conversation: [], attachments: [], canDrop: true, artifact: {deliverable: {name: "Watering animation", evidence: [{ label: "Play the watering animation", href: "/review/watering" }]}}, evidence: [{ label: "Run notes", text: "Frames checked" }] }, {});
assert.ok(index(animation, "Does the motion read clearly?") < index(animation, "Play the watering animation"));
assert.ok(index(animation, "Play the watering animation") < index(animation, "What I recommend"));
const design = queue.qPaneHtml({ id: "design", question: "Which tool should players receive first?", title: "First tool", source: "decision card design", owner: { name: "Milo" }, answer: "Watering can", why: "It teaches the core loop.", instead: "Hoe", options: [{ label: "Watering can", detail: "Care for a planted crop." }], followUps: [], conversation: [], attachments: [], canDrop: false, deliverableEvidence: [], evidence: [{ label: "Design comparison", text: "Both choices shown" }] }, {});
assert.ok(index(design, "Which tool should players receive first?") < index(design, "What I recommend"));
assert.ok(index(design, "What I recommend") < index(design, "What yes starts"));
const incomplete = queue.qPaneHtml({ id: "incomplete", kind: "review", question: "Does this result stand despite the missing recommendation?", title: "Review: Crop icon", source: "work card incomplete", owner: { name: "Yuki" }, answer: "", why: "", instead: "", options: [], followUps: [], conversation: [], attachments: [], canDrop: true, artifact: {deliverable: {name: "Crop icon", evidence: [{ label: "Open the crop icon", href: "/review/icon" }]}}, evidence: [], }, {});
assert.ok(index(incomplete, "Does this result stand despite the missing recommendation?") < index(incomplete, "Open the crop icon"));
assert.ok(index(incomplete, "Open the crop icon") < index(incomplete, "No recommendation on this one."));
const work = vm.createContext({ ...shared });
vm.runInContext(reviewSource, work);
// work.js is loaded after app.js in the browser. Supply its one shared
// workflow adapter here too; an isolated VM must not silently replace that
// public projection with a second, different status calculation.
const workflowHelper = appSource.slice(appSource.indexOf("function workflowView("), appSource.indexOf("// A work title"));
vm.runInContext(workflowHelper, work);
vm.runInContext(fs.readFileSync(root + "/hq/static/work.js", "utf8"), work);
const card = work.workCard({ id: "work-animation", title: "Internal animation task", state: "for_review", owner: "rin", level: "task", deliverable: { name: "Watering animation", evidence: [{ label: "Play the watering animation", href: "/review/watering" }] }, recommend: { question: "Does the motion read clearly?", answer: "Keep this timing", why: "The pause reads at game size.", instead: "Slow it down" }, result: "The frames are ready." }, {}, {}).html;
assert.ok(index(card, "Play the watering animation") < index(card, "Does the motion read clearly?"));
assert.ok(index(card, "Does the motion read clearly?") < index(card, "Recommended"));
assert.ok(index(card, "Recommended") < index(card, "The frames are ready."));
// Supported production path entries use only the already-served repo roots.
const schemaCard = { id: "path-review", title: "Path evidence", state: "for_review", owner: "rin", level: "task",
  recommend: { question: "Keep this?", answer: "Keep it", why: "Clear", instead: "Revise" },
  deliverable: { name: "Path evidence", evidence: [
    { label: "Asset image", path: "assets/anim/sunflower_bloom/sheet.png" },
    { label: "Design notes", path: "docs/design/mockups/example image.png" },
    { label: "Loop", path: "tools/experiments/out/seeder_bot/seeder_bot.gif" },
    { label: "Safe fragment", href: "#/design/anim/seeder_bot" },
    { label: "Safe web", href: "https://example.com/review" },
    { label: "Unsafe script", href: "javascript:alert(1)" },
    { label: "Unsafe data", href: "data:text/html,hi" },
    { label: "Unsafe mixed case", href: "JaVaScRiPt:alert(1)" },
    { label: "Unsafe newline", href: "java\nscript:alert(1)" },
    { label: "Unsafe file", href: "file:///etc/passwd" },
    { label: "Unsafe path", path: "docs/../../etc/passwd" },
    { label: "Absolute path", path: "/etc/passwd" },
    { label: "Private repo data", path: "hq/data/org.json" },
  ] } };
const schemaQueue = queue.qPaneHtml(queue.qWorkItem(schemaCard, {}, ""), {});
const schemaLegacy = work.workCard(schemaCard, {}, {}).html;
for (const html of [schemaQueue, schemaLegacy]) {
  for (const href of ["/assets/anim/sunflower_bloom/sheet.png", "/docs/design/mockups/example%20image.png", "/loops/seeder_bot/seeder_bot.gif", "#/design/anim/seeder_bot", "https://example.com/review"])
    assert.ok(html.includes('href="' + href + '"'), href);
  assert.ok(!html.includes("Unsafe"));
  assert.ok(!html.includes("Absolute path"));
  assert.ok(!html.includes("Private repo data"));
}
// These are recorded repository cards, not invented example rows. Their missing
// deliverable fields must remain missing; the positive cases above test new evidence.
const readCard = (kind, id) => JSON.parse(fs.readFileSync(root + "/hq/data/" + kind + "/" + id + ".json", "utf8"));
const actualAnimation = readCard("work", "wr1788991284fa19");
const actualIncomplete = readCard("work", "w449aff92129");
const actualDesign = readCard("decisions", "Q-107");
const seeder = queue.qPaneHtml(queue.qWorkItem(actualAnimation, {}, "Recorded review"), {});
assert.ok(seeder.includes('href="/assets/anim/seeder_bot/sheet.png"'), "seeder review links to the displayed sheet beside its heading");
assert.ok(seeder.includes("does not identify the exact render originally reviewed"), "legacy display does not claim a pinned version");
assert.ok(seeder.includes('data-review-slug="seeder_bot"') && seeder.includes("Currently exported game animation"),
  "seeder review offers the playable game export while distinguishing it from the unpinned original");
const audioChoice = readCard("decisions", "Q-102");
const audioHtml = queue.qPaneHtml(queue.qDecisionItem(audioChoice, {}, { seats: [] }), {});
assert.equal((audioHtml.match(/<audio /g) || []).length, 3, "all recorded rival sounds are listenable");
const storyHtml = queue.qPaneHtml(queue.qDecisionItem(actualDesign, {}, { seats: [] }), {});
assert.ok((storyHtml.match(/<video /g) || []).length >= 3, "story-night rivals remain playable");
assert.ok(storyHtml.includes("The robot&#39;s treads") || storyHtml.includes("The robot's treads"), "rivals retain their groups");
const comparison = queue.reviewComparison({deliverable: {reviewed_version: "sha256:example", created_at: "2026-09-24",
  comparison: {copy: [{label: "Current", text: "Plant crop"}, {label: "Proposed", text: "Sow a seed"}],
    rows: [{label: "Seed cost", current: 3, proposed: 2}]}, evidence: [
    {label: "Current loop", role: "Current", path: "tools/experiments/out/crow_gorge/current.gif"},
    {label: "Proposed loop", role: "Proposed", path: "tools/experiments/out/crow_gorge/proposed.gif"}]}});
assert.equal((comparison.match(/<img /g) || []).length, 2, "both animations are visible at once");
assert.ok(comparison.includes("Plant crop") && comparison.includes("Sow a seed"), "copy versions are readable together");
assert.ok(comparison.includes("<table") && comparison.includes("Seed cost"), "numeric choices use a table");
assert.ok(comparison.includes("Created:") && comparison.includes("Displayed here:") && comparison.includes("Reviewed version:"), "three artifact states remain distinct");
for (const recorded of [actualAnimation, actualIncomplete]) {
  const row = queue.qWorkItem(recorded, {}, "Recorded review");
  const html = queue.qPaneHtml(row, {});
  assert.ok(html.includes(recorded.title), "legacy review retains its actual title");
  assert.equal(row.deliverableEvidence.length, 0, "does not invent evidence for old cards");
  if (recorded.recommend && recorded.recommend.question)
    assert.ok(index(html, recorded.recommend.question) < index(html, "What I recommend"));
  else assert.ok(html.includes("No recommendation on this one."));
  const legacy = work.workCard(recorded, {}, {}).html;
  assert.ok(legacy.includes(recorded.title));
  if (recorded.state === "for_review")
    assert.ok(legacy.includes('data-act="drop"'), "a reviewable result can be rejected");
  else assert.ok(!legacy.includes('data-act="drop"'), "a closed result cannot be rejected twice");
  assert.ok(legacy.includes('data-send="' + recorded.id + '"'), "recorded incomplete result keeps Comment");
  assert.ok(legacy.includes(recorded.ask), "the original ask remains available");
}
const choice = queue.qPaneHtml(queue.qDecisionItem(actualDesign, {}, { seats: [] }), {});
for (const option of actualDesign.options) assert.ok(choice.includes('value="' + option.key + '"'));
assert.equal((choice.match(/type="radio"/g) || []).length, actualDesign.options.length + 1);
assert.equal((choice.match(/class="q-decision-submit"/g) || []).length, 1);
assert.ok(choice.includes('data-intent="revise"'));
assert.ok(index(choice, "Result to review") < index(choice, "What I recommend"));
console.log("Rendered review cards keep question, artifact, recommendation, and result in order.");
'''
        rendered = subprocess.run(["node", "-e", renderer_test, os.path.dirname(os.path.dirname(HERE))],
                                 text=True, capture_output=True)
        check(rendered.returncode == 0, "animation, design-choice and incomplete cards render their human briefs in order")
        if rendered.returncode:
            print(rendered.stderr)

        server.work.items = lambda **kwargs: (_ for _ in ()).throw(OSError("unreadable"))
        unavailable = server.waiting_on_you()
        check(unavailable["available"] is False and unavailable["count"] is None,
              "an unavailable work reading is not reported as zero")
    finally:
        server.api_queue, server.work.items, server.work._held_back = old_queue, old_items, old_held

    code_result = card("w-code-result", "for_review", tier=1,
                       diff={"applied": True, "files": ["systems/weather.gd"]},
                       suites={"unit": {"ok": True}}, check={"verdict": "pass"})
    blocked_code = card("w-code-held", "for_review", tier=1,
                        diff={"applied": True, "files": ["systems/weather.gd"]},
                        repair_hold="The candidate needs reconciliation.")
    uncommitted_code = card("w-uncommitted", "for_review", tier=1,
                            diff={"applied": False, "why_not": "overlaps uncommitted files"},
                            workflow_view={"blocker": {"type": "code_conflict",
                                                        "reason": "The candidate overlaps uncommitted files."}})
    actual_choice = card("w-tier-two-choice", "needs_approval", tier=2)
    projected_fixture = Path(HERE) / "fixtures" / "blocked_reconciliation_view.json"
    projected_item = {"id": "weather", "state": "waiting_session", "owner": "rin",
                      "created": "2026-09-22T10:00:00Z", "tier": 1}
    check(json.loads(projected_fixture.read_text()) == server.work.work_view(
        projected_item, {"blocked_files": ["systems/weather.gd"],
                         "tree_reason": "Save-lineage edits overlap the old patch"}, now=1790100000),
        "browser fixture is exactly the backend's blocked-outcome/runnable-action projection")
    with patch.object(server, "api_queue", return_value={"items": [], "curated": [], "decided": [], "rulings": {}}), \
         patch.object(server.work, "items", return_value=[code_result, blocked_code,
                                                           uncommitted_code, actual_choice]):
        held_view = server.work.work_view(blocked_code, now=1000)
        check(held_view["availability"] == "runnable" and held_view["blocker"]
              and held_view["next_action"]["type"] == "reconcile",
              "real projection has a runnable reconciliation step beside a blocked code result")
        projection = server.waiting_on_you()
        check({row["source_id"] for row in projection["ready"]} == {"w-tier-two-choice"},
              "applied but unlanded code is not Daniel's work; a tier-two approval still is")
        check(projection["counts"] == {"total": 1, "work": 1, "decisions": 0}
              and server.waiting_reading()["count"] == 1
              and server.waiting_block()["count"] == 1,
              "dashboard and navigation counts exclude both studio-owned code results")
        with patch.object(server.work, "HOST", server):
            snapshot = server.work.snapshot()
        check(snapshot["waiting_on_you"] == projection["counts"]["work"] == 1
              and snapshot["unprepped"] == 0,
              "Work counts use the same canonical predicate as the verdict inbox")
        statuses = {row["source_id"]: row for row in projection["items"]}
        check(all(statuses[ident]["status"] == "verification_pending" for ident in
                  ("w-code-result", "w-code-held", "w-uncommitted")),
              "the studio's missing landing evidence stays visible without a CEO verdict")
        signals = server._compute_signals_now()
        check(signals["work"]["waiting_on_you"] == signals["waiting"]["count"] == 1
              and any("Give your verdict on 1 piece" in row.get("headline", "")
                      for row in signals["eye"]),
              "dashboard count and verdict hero include only the genuine tier-two approval")
        with patch.object(server.work, "items", return_value=[code_result, blocked_code]):
            signals = server._compute_signals_now()
        check(signals["work"]["waiting_on_you"] == signals["waiting"]["count"] == 0
              and not any("Give your verdict" in row.get("headline", "")
                          for row in signals["eye"]),
              "dashboard has no verdict hero when only studio-owned code is held")

    concrete = {"title": "Fix the preview", "owner": "rin",
                "first_action": "Render the revised animation at game size", "tier": 1}
    for field, value in (("follow_ups", []), ("follow_ups", [concrete]), ("follow_up", concrete)):
        sample = card("w-valid-consequence", "for_review")
        sample.pop("follow_ups")
        sample[field] = value
        check(server.work_preparation(sample)["ready"],
              f"{field} accepts concrete next work or canonical explicit no-work")
    for field in ("follow_ups", "follow_up"):
        malformed = [None, "", " ", {}, False, 0, "NONE", [None], [""], [{}],
                     {"title": "Incomplete"}, [concrete, None],
                     {**concrete, "first_action": " "}, {**concrete, "tier": "1"}]
        if field == "follow_up":
            malformed.append([])
        else:
            malformed.extend([concrete, [{**concrete, "title": {}}], [{**concrete, "owner": ""}]])
        for value in malformed:
            sample = card("w-bad-consequence", "for_review")
            sample.pop("follow_ups")
            sample[field] = value
            check(server.work_preparation(sample)["missing"] == ["consequences"],
                  f"{field} rejects malformed consequence {value!r}")
            with patch.object(server, "api_queue", return_value={"curated": [], "rulings": {}, "decided": []}), \
                 patch.object(server.work, "items", return_value=[sample]):
                projected = server.waiting_on_you()
            check(projected["available"] and projected["count"] == 0
                  and projected["items"][0]["preparation"]["missing"] == ["consequences"],
                  "malformed consequences stay visible as preparation gaps, not ready work")
    sample = card("w-conflicting-consequence", "for_review", follow_up=None)
    check(server.work_preparation(sample)["missing"] == ["consequences"],
          "an explicit empty list does not mask a malformed singular consequence")

    # Exercise production readers rather than replacing them with throwing stubs.
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        for directory in ("work", "decisions", "rulings"):
            (root / directory).mkdir()
        good = card("w-good", "for_review")
        (root / "work" / "good.json").write_text(json.dumps(good))
        (root / "decisions" / "q.json").write_text(json.dumps({"id": "Q-1"}))
        (root / "rulings" / "q.json").write_text(json.dumps({"id": "Q-1", "option": "yes"}))
        with patch.object(server, "DATA", tmp), patch.object(server.work, "WORK", str(root / "work")), \
             patch.object(server.work, "HOST", server), patch.object(server, "parse_queue", side_effect=OSError("raw Markdown unavailable")):
            check(server.waiting_on_you()["count"] == 1, "real complete readers exclude a settled decision")
            for directory in ("work", "decisions", "rulings"):
                bad = root / directory / "bad.json"
                bad.write_text("{invalid json")
                got = server.waiting_on_you()
                check(got["available"] is False and got["count"] is None,
                      f"malformed {directory} record makes the complete reading unavailable")
                if directory == "work":
                    check(len(server.work.items()) == 1, "legacy work reader still exposes the valid record")
                bad.unlink()
                folder = root / directory
                absent = root / (directory + "-saved")
                folder.rename(absent)
                got = server.waiting_on_you()
                check(got["available"] is False and got["count"] is None,
                      f"missing {directory} directory cannot publish a partial count")
                folder.write_text("not a directory")
                check(server.waiting_on_you()["available"] is False,
                      f"a file replacing {directory} is unavailable")
                folder.unlink()
                absent.rename(folder)
                listdir = os.listdir
                def denied(path, blocked=str(folder)):
                    if str(path) == blocked:
                        raise PermissionError("fixture denies the required directory")
                    return listdir(path)
                with patch("os.listdir", side_effect=denied):
                    check(server.waiting_on_you()["available"] is False,
                          f"unreadable {directory} directory is unavailable")
            (root / "work" / "bad.json").write_text(json.dumps({
                "id": "w-nested", "state": "for_review", "diff": "not a mapping"}))
            check(server.waiting_on_you()["available"] is False,
                  "invalid nested work data is caught inside the availability boundary")
            (root / "work" / "bad.json").unlink()
            (root / "decisions" / "bad.json").write_text(json.dumps({
                "id": "Q-2", "replies": [None]}))
            (root / "rulings" / "bad.json").write_text(json.dumps({
                "id": "Q-2", "judgment": "revise", "ruled_at": "2026-09-21"}))
            check(server.waiting_on_you()["available"] is False,
                  "invalid nested decision data is caught inside the availability boundary")

    # Exercise real routing and file reads without starting a service.
    import io
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        outside = root / "private.txt"
        outside.write_bytes(b"private")
        for route, directory in (("docs", "docs"), ("assets", "assets"),
                                 ("loops", server.anim.LOOPS_DIR)):
            served = root / directory
            served.mkdir(parents=True, exist_ok=True)
            (served / "review image.png").write_bytes(b"review evidence")
            (served / "%20.txt").write_bytes(b"decoded once")
            (served / "escape.txt").symlink_to(outside)
            def request(suffix):
                handler = object.__new__(server.Handler)
                handler.path = "/" + route + "/" + suffix
                handler.wfile = io.BytesIO()
                codes = []
                handler.send_response = codes.append
                handler.send_header = lambda *args: None
                handler.end_headers = lambda: None
                with patch.object(server, "REPO", tmp), patch.object(server, "USER_WORKSPACE", tmp):
                    handler.do_GET()
                return codes[-1], handler.wfile.getvalue()
            check(request("review%20image.png") == (200, b"review evidence"),
                  f"{route} routing serves a real filename containing a space")
            check(request("%2520.txt") == (200, b"decoded once"),
                  f"{route} routing decodes exactly once")
            for unsafe in ("%2e%2e/private.txt", "../private.txt", "%2Fprivate.txt",
                           "folder%2fprivate.txt", "%5cprivate.txt", "%00.png",
                           "bad%.png", "bad%2.png", "bad%gg.png", "%ff.png", "escape.txt"):
                code, body = request(unsafe)
                check(code in (400, 403) and body != b"private",
                      f"{route} rejects unsafe file path {unsafe}")

    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
