// The Animation Lab may only report success after the queue's exact review
// card confirms its persisted transition.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const source = fs.readFileSync(path.join(__dirname, "../static/anim.js"), "utf8");
const start = source.indexOf("function anWireVerdict");
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
    querySelectorAll(selector) { return selector === ".an-verdicts button" ? ui.buttons : []; },
  },
  fetch: async (url, options) => {
    assert.equal(url, "/api/loop/verdict");
    posted = JSON.parse(options.body);
    return { ok: answer.httpOk !== false, status: answer.status || 200,
      json: async () => answer.body };
  },
});
vm.runInContext(source.slice(start, end), ctx);

async function submit(verdict, response, reason = "The timing reads clearly at game size.") {
  ui = makeUi();
  answer = response;
  posted = null;
  ctx.anWireVerdict({ slug: "watering", work_item: "w123456abcdef" });
  ui.why.value = reason;
  await ui.buttons.find(button => button.dataset.v === verdict).onclick();
  assert.deepEqual(posted, { work_id: "w123456abcdef", slug: "watering", verdict, why: reason });
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

  assert.match(source, /L\.work_item \? `<div class="an-verdicts">/,
    "a loop without a safe review identity has no verdict controls");
  assert.match(source, /href="#\/work\/\$\{encodeURIComponent\(L\.work_item\)\}"/,
    "an identified loop links to the same authoritative review card");
  console.log("Animation Lab verdicts confirm keep, drop and rework on the exact queue record.");
})().catch(error => { console.error(error); process.exitCode = 1; });
