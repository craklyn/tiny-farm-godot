// Behavioral checks for the two browser paths that record decisions.
//
// These tests drive the same click handlers and POST helpers the browser uses.
// The fake server persists each accepted payload to disk so a rendered label
// cannot pass in place of the recorded outcome.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const vm = require("node:vm");

const root = path.join(__dirname, "../..");
const appSource = fs.readFileSync(path.join(root, "hq/static/app.js"), "utf8");
const queueSource = fs.readFileSync(path.join(root, "hq/static/queue.js"), "utf8");
const workSource = fs.readFileSync(path.join(root, "hq/static/work.js"), "utf8");
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "hq-decision-actions-"));
const alerts = [];

function control() {
  return { dataset: {}, disabled: false, textContent: "", listeners: {},
    addEventListener(type, fn) { this.listeners[type] = fn; },
    click() { return this.listeners.click(); } };
}

function classList() { return { toggle() {}, add() {}, remove() {} }; }

function decisionElement(html) {
  const radios = [...html.matchAll(/<input type="radio"[^>]*value="([^"]*)"[^>]*data-intent="([^"]*)"[^>]*data-label="([^"]*)"/g)]
    .map(match => {
      const option = { classList: classList() };
      return { value: match[1], dataset: { intent: match[2], label: match[3] }, checked: false,
        disabled: false, listeners: {}, closest: () => option,
        addEventListener(type, fn) { this.listeners[type] = fn; },
        choose() { radios.forEach(r => { r.checked = false; }); this.checked = true; this.listeners.change(); } };
    });
  const firstRow = { children: [], appendChild(value) { this.children.push(value); }, remove() {} };
  const ask = { hidden: false };
  const done = { innerHTML: "", querySelector: () => null };
  const textarea = { value: "", disabled: false, listeners: {},
    addEventListener(type, fn) { this.listeners[type] = fn; }, focus() {},
    type(value) { this.value = value; this.listeners.input(); } };
  const button = control();
  const note = { textContent: "" };
  const card = {
    radios, textarea, button, note,
    querySelector(selector) {
      return ({ ".d-att-first": firstRow, ".d-thread": null, ".d-ask": ask,
        ".d-done": done, ".d-say": textarea, ".d-record": button,
        ".d-consequence": note })[selector] ?? null;
    },
    querySelectorAll(selector) { return selector.startsWith('input[name="opt-') ? radios : []; },
  };
  return { firstElementChild: card };
}

const decisions = new Map();
function fakeFetch(url, options) {
  assert.equal(url, "/api/ruling");
  const body = JSON.parse(options.body);
  const choices = decisions.get(body.id);
  let error = "";
  if (!choices) error = "no such decision";
  else if (body.intent === "choose" && !choices.has(body.option)) error = "that option is not on this decision";
  else if (body.intent === "revise" && !body.judgment.trim()) error = "tell the studio what to revise";
  const ruling = { id: body.id, intent: body.intent, option: body.option || null,
    option_label: body.option && choices ? choices.get(body.option) : null, judgment: body.judgment || null,
    status: "pending_integration" };
  if (!error) fs.writeFileSync(path.join(tmp, body.id + ".json"), JSON.stringify(ruling));
  return Promise.resolve({ ok: !error, status: error ? 400 : 200,
    json: async () => error ? { error } : { ok: true, ruling } });
}

const ctx = vm.createContext({ console, Date, Math, globalThis: {}, fetch: fakeFetch,
  alert: message => alerts.push(message), esc: String, md: String, mdi: String,
  h: decisionElement, attachmentEl() { throw new Error("no attachments expected"); },
  location: { hash: "#/work" }, renderWork() {}, encodeURIComponent,
});
const actionStart = appSource.indexOf("function ruleWhen");
const actionEnd = appSource.indexOf("\n\n/* ---------------- chat", actionStart);
vm.runInContext(appSource.slice(actionStart, actionEnd), ctx);
const advanceStart = workSource.indexOf("function advanceDirectDecision");
const advanceEnd = workSource.indexOf("\n\nasync function renderWork", advanceStart);
vm.runInContext(workSource.slice(advanceStart, advanceEnd), ctx);
const queueSubmitStart = queueSource.indexOf("async function qSubmitDecision");
const queueSubmitEnd = queueSource.indexOf("\n\n/* The side pane", queueSubmitStart);
vm.runInContext("let qSelected = null;\n" + queueSource.slice(queueSubmitStart, queueSubmitEnd), ctx);

function recorded(id) { return JSON.parse(fs.readFileSync(path.join(tmp, id + ".json"), "utf8")); }

async function directCardScenario(id, options, optionIndex, feedback, nextId) {
  decisions.set(id, new Map(options.map(option => [option.key, option.label])));
  const card = ctx.decisionCard({ id, title: id, question: "Choose", options }, null, {},
    () => ctx.advanceDirectDecision(id, [{ id }, { id: nextId }], id), {});
  ctx.location.hash = "#/inbox/" + id;
  const radio = card.radios[optionIndex];
  radio.choose();
  if (feedback) card.textarea.type(feedback);
  assert.equal(card.button.disabled, false, `${id} enables its recorded action`);
  await card.button.click();
  assert.equal(ctx.location.hash, "#/inbox/" + nextId, `${id} advances to the next direct card`);
  return recorded(id);
}

(async () => {
  const yes = await directCardScenario("Q-yes", [
    { key: "yes", label: "Yes — keep the porch (Recommended)", detail: "It reads clearly." },
    { key: "no", label: "No — remove it", detail: "More yard." },
  ], 0, "Keep the warm light.", "Q-after-yes");
  assert.equal(yes.option, "yes");
  assert.equal(yes.judgment, "Keep the warm light.");

  const no = await directCardScenario("Q-no", [
    { key: "yes", label: "Yes — add it", detail: "More motion." },
    { key: "no", label: "No — leave the field quiet (Recommended)", detail: "The field already reads." },
  ], 1, "The stillness is the point.", "Q-after-no");
  assert.equal(no.option, "no", "a negative recommendation records the negative option");

  const revised = await directCardScenario("Q-revise", [
    { key: "a", label: "First layout", detail: "Compact." },
  ], 1, "Show the window at game size first.", "Q-after-revision");
  assert.equal(revised.intent, "revise");
  assert.equal(revised.option, null, "a revision does not settle the question");

  decisions.set("Q-queue", new Map([["no", "No — keep the current timing (Recommended)"]]));
  const queueControl = control();
  const selected = { value: "no", dataset: { intent: "choose", label: "No — keep the current timing (Recommended)" } };
  const status = { textContent: "" };
  vm.runInContext('qSelected = "Q-queue"', ctx);
  let visible = [{ id: "Q-queue" }, { id: "Q-next" }];
  const ok = await ctx.qSubmitDecision(queueControl, { cardId: "Q-queue" }, selected, "No change needed.", status, async () => {
    visible = visible.slice(1);
    return ctx.qSelectNext(visible);
  });
  assert.equal(ok, true);
  assert.equal(recorded("Q-queue").option, "no", "the queue handler persists the chosen option");
  assert.equal(ctx.qSelectNext(visible), "Q-next", "the queue selects the next visible question after persistence");

  const failed = control();
  const failedStatus = { textContent: "" };
  const failedOk = await ctx.qSubmitDecision(failed, { cardId: "Q-missing" }, selected, "", failedStatus,
    async () => { throw new Error("must not refresh after a rejected write"); });
  assert.equal(failedOk, false);
  assert.equal(failed.disabled, false);
  assert.match(failedStatus.textContent, /no such decision/);
  assert.equal(alerts.length, 0);
  console.log("Decision actions persist Yes, No and revision outcomes and advance both review flows.");
})().catch(error => { console.error(error); process.exitCode = 1; })
  .finally(() => fs.rmSync(tmp, { recursive: true, force: true }));
