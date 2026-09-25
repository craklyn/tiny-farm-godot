// The Animation Lab may only report success after the queue's exact review
// card confirms its persisted transition.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const source = fs.readFileSync(path.join(__dirname, "../static/anim.js"), "utf8");
const start = source.indexOf("function anCallCard");
const end = source.indexOf("\n\n/* ---------- the instruments", start);
let ui;
let answer;
let posted;

function makeUi() {
  const asks = { open: false };
  const why = { value: "", disabled: false, listeners: {}, focused: false,
    addEventListener(type, fn) { this.listeners[type] = fn; }, focus() { this.focused = true; } };
  const note = { className: "small muted", textContent: "" };
  const buttons = ["keep", "rework", "drop"].map(verdict => ({
    dataset: { v: verdict }, disabled: false, listeners: {}, onclick: null,
    addEventListener(type, fn) { this.listeners[type] = fn; },
  }));
  return { asks, why, note, buttons };
}

const ctx = vm.createContext({
  document: {
    getElementById(id) { return ({ "an-why": ui.why, "an-callnote": ui.note, "an-asks": ui.asks })[id] || null; },
    querySelector() { return null; },
    querySelectorAll(selector) {
      if (selector === ".an-verdicts button") return ui.buttons;
      if (selector === ".an-params input[data-p]") return [{ dataset: { p: "speed" }, value: "2.5" }];
      return [];
    },
  },
  anPlayer: { judgedValues: { speed: 2.5 } },
  esc: s => String(s ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;",
    '"': "&quot;", "'": "&#39;" }[c])),
  fetch: async (url, options) => {
    assert.equal(url, "/api/loop/verdict");
    posted = JSON.parse(options.body);
    return { ok: answer.httpOk !== false, status: answer.status || 200,
      json: async () => answer.body };
  },
});
vm.runInContext(source.slice(start, end), ctx);

async function submit(verdict, response, reason = "The timing reads clearly at game size.",
                      workItem = "w123456abcdef") {
  ui = makeUi();
  answer = response;
  posted = null;
  ctx.anWireVerdict({ slug: "watering", work_item: workItem });
  ui.why.value = reason;
  await ui.buttons.find(button => button.dataset.v === verdict).onclick();
  assert.deepEqual(posted, { work_id: workItem, slug: "watering", verdict,
    why: reason, values: { speed: 2.5 } });
  return ui;
}

(async () => {
  for (const [verdict, state] of [["keep", "accepted"], ["drop", "dropped"]]) {
    const result = await submit(verdict, { body: { ok: true, verdict, work_id: "w123456abcdef", state,
      note: verdict === "keep" ? "Kept." : "Dropped." } });
    assert.equal(result.why.disabled, true, `${verdict} locks the recorded review`);
    assert.ok(result.buttons.every(button => button.disabled), `${verdict} cannot be submitted twice`);
    assert.match(result.note.textContent, verdict === "keep" ? /Kept/ : /Dropped/);
  }

  const rework = await submit("rework", { body: { ok: true, verdict: "rework",
    work_id: "w123456abcdef", state: "doing", run: { id: "r1" } } },
  "Hold the anticipation for two more frames.");
  assert.equal(rework.why.disabled, true);
  assert.ok(rework.buttons.every(button => button.disabled));
  assert.match(rework.note.textContent, /being reworked now/);

  const mismatch = await submit("keep", { body: { ok: true, verdict: "keep",
    work_id: "w999999999999", state: "accepted", note: "Kept." } });
  assert.equal(mismatch.why.disabled, false, "an unconfirmed transition remains actionable");
  assert.ok(mismatch.buttons.every(button => !button.disabled));
  assert.match(mismatch.note.textContent, /did not confirm the recorded card transition/);

  const rejected = await submit("drop", { httpOk: false, status: 409,
    body: { error: "that review is no longer waiting for a verdict" } });
  assert.ok(rejected.buttons.every(button => !button.disabled));
  assert.match(rejected.note.textContent, /no longer waiting/);

  ui = makeUi();
  answer = { body: {} };
  posted = null;
  ctx.anWireVerdict({ slug: "watering", work_item: "w123456abcdef" });
  await ui.buttons[0].onclick();
  assert.equal(posted, null, "a blank reason never reaches the server");
  assert.equal(ui.why.focused, true);
  assert.match(ui.note.textContent, /Say why first/);

  ui = makeUi();
  ui.why.value = "Looks good";
  posted = null;
  ctx.anPlayer = { judgedValues: { speed: 1 } };
  ctx.anWireVerdict({ slug: "watering", work_item: "w123456abcdef" });
  await ui.buttons[0].onclick();
  assert.equal(posted, null, "a slider value that is not on stage cannot be judged");
  assert.match(ui.note.textContent, /Wait for the preview/);
  ctx.anPlayer = { judgedValues: { speed: 2.5 } };

  // A hand-drawn loop has no card yet: its first verdict files one, and only a
  // response that says it filed a card counts as recorded.
  const filed = await submit("keep", { body: { ok: true, verdict: "keep", work_id: "wfeedface0001",
    state: "accepted", filed: true, note: "Kept." } }, "Reads at game size.", null);
  assert.equal(filed.why.disabled, true, "a filed card confirms a hand-drawn loop's verdict");
  const unfiled = await submit("keep", { body: { ok: true, verdict: "keep", work_id: "wfeedface0001",
    state: "accepted", note: "Kept." } }, "Reads at game size.", null);
  assert.equal(unfiled.why.disabled, false, "a verdict that names no filed card is not recorded");

  const open = ctx.anCallCard({ slug: "watering", work_item: "w123456abcdef" });
  assert.match(open, /data-v="keep"/);
  assert.match(open, /href="#\/work\/w123456abcdef"/, "the buttons name the queue's own card");
  const hand = ctx.anCallCard({ slug: "watering", work_item: null });
  assert.match(hand, /data-v="drop"/, "a loop with no card can still be judged");
  assert.match(hand, /files one to the\s+art director/);
  const judged = ctx.anCallCard({ slug: "watering", work_item: null, review: {
    id: "wr1788991284fa19", state: "accepted", owner: "ingrid", owner_name: "Ingrid Bauer",
    verdict: "keep", reason: "The hop <reads>", at: "2026-09-25T10:00",
    answer: { text: "Landing it with the speed you judged.", at: "2026-09-25T10:01" } } });
  assert.doesNotMatch(judged, /data-v=/, "a judged loop is not judged twice from the page");
  assert.match(judged, /You kept it/);
  assert.match(judged, /The hop &lt;reads&gt;/, "his reason is shown, escaped");
  assert.match(judged, /data-person="ingrid">Ingrid Bauer<\/a> answered/);
  assert.match(judged, /Landing it with the speed you judged/);
  assert.match(judged, /href="#\/work\/wr1788991284fa19"/);
  const waiting = ctx.anCallCard({ slug: "watering", review: { id: "wa1234567", state: "dropped",
    owner: "ingrid", owner_name: "Ingrid Bauer", verdict: "drop", reason: "Too busy", answer: null } });
  assert.match(waiting, /You dropped it/);
  assert.match(waiting, /has not answered yet/);
  console.log("Animation Lab verdicts confirm keep, drop and rework on the exact queue record.");
})().catch(error => { console.error(error); process.exitCode = 1; });
