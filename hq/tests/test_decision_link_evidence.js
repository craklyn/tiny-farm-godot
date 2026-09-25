// §11 live-data finding: Q-122 and Q-123 (2026-09-25) put evidence images in
// a decision card's `links` field, in the same {type, src, caption} shape
// `attachments` uses, because hq/README.md documents `links` as plain
// references. Nothing rendered them — the queue pane and the direct decision
// page both showed the recommendation and a paragraph promising "the attached
// boards" with no board in sight. These checks pin the fix: a media-typed
// link is treated as evidence wherever an attachment would be, and a plain
// reference link still renders, however it arrived.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const root = path.join(__dirname, "../..");
const reviewSource = fs.readFileSync(path.join(root, "hq/static/review_evidence.js"), "utf8");
const queueSource = fs.readFileSync(path.join(root, "hq/static/queue.js"), "utf8");
const appSource = fs.readFileSync(path.join(root, "hq/static/app.js"), "utf8");

// --- Pure helpers (review_evidence.js) --------------------------------------
const helperCtx = vm.createContext({ esc: String, console });
vm.runInContext(reviewSource, helperCtx);

const mixedLinks = [
  { type: "image", src: "docs/design/mockups/palette_quantize/obstacle_rock_compare.png", caption: "The rock" },
  { label: "Q-122 in the designer queue", href: "https://example.com/queue" },
  "docs/plain/bare-path.md",
  { type: "audio", src: "docs/design/mockups/sound.ogg", caption: "The pick" },
  null,
];

const evidence = helperCtx.linkEvidenceAttachments(mixedLinks);
assert.equal(evidence.length, 2, "only the media-typed entries become evidence");
assert.deepEqual(evidence.map(e => e.type), ["image", "audio"]);
assert.equal(evidence[0].src, "docs/design/mockups/palette_quantize/obstacle_rock_compare.png");

const refs = helperCtx.linkReferenceEntries(mixedLinks);
// Everything that is not a recognized media type stays a reference,
// including the null entry — the original renderer already tolerated a
// malformed link rather than taking the whole card down (app.js's own
// comment: "a card that cannot render must never take the whole inbox down").
assert.equal(refs.length, 3, "the reference link, the bare path and the malformed entry are not evidence");

const renderedRefs = helperCtx.renderReferenceLinks(mixedLinks);
assert.match(renderedRefs, /Q-122 in the designer queue/);
assert.match(renderedRefs, /bare-path\.md/);
assert.doesNotMatch(renderedRefs, /The rock/, "a media caption does not also print as a bare reference link");
assert.equal(helperCtx.renderReferenceLinks([]), "");
assert.equal(helperCtx.renderReferenceLinks(undefined), "");
assert.equal(helperCtx.linkEvidenceAttachments(undefined).length, 0);

// --- queue.js: qWorkItem / qDecisionItem merge links into attachments -------
const queueCtx = vm.createContext({
  console, esc: String, md: String, mdi: String,
  ownerOf: () => ({ name: "Yuki Tanaka", emoji: "🎨" }),
  reviewTitle: card => "Review: " + card.title,
  reviewEvidenceLinks: () => [],
  document: { addEventListener() {} },
  routes: {}, renderQueue: () => {}, route: () => {}, location: { hash: "#/" },
  followUps: () => [],
});
vm.runInContext(reviewSource, queueCtx);
vm.runInContext(queueSource, queueCtx);

const q122 = {
  id: "Q-122", owner: "yuki", title: "Should the rock and the fox sprites be redrawn with fewer colours?",
  why_now: "The cleanup step landed today.",
  options: [{ key: "a", label: "Replace both (Recommended)", detail: "Clears the defect." }],
  links: [
    { type: "image", src: "docs/design/mockups/palette_quantize/obstacle_rock_compare.png", caption: "The rock obstacle" },
    { type: "image", src: "docs/design/mockups/palette_quantize/fox_compare.png", caption: "The fox" },
    { label: "Q-122 in the designer queue", href: "https://example.com/queue" },
  ],
};
const decisionRow = queueCtx.qDecisionItem(q122, {}, {});
assert.equal(decisionRow.attachments.length, 2, "both image links reach the row as attachments");
// Array.from: the row's arrays are built inside the vm context, so they carry
// that realm's Array constructor — deepStrictEqual treats an otherwise
// identical array as different when the constructors differ.
assert.deepEqual(Array.from(decisionRow.attachments, a => a.caption), ["The rock obstacle", "The fox"]);
assert.equal(decisionRow.links.length, 3, "the raw links (including the reference) are preserved for renderReferenceLinks");

const noEvidenceCard = { id: "Q-1", owner: "yuki", title: "A decision with no links at all", options: [] };
assert.equal(queueCtx.qDecisionItem(noEvidenceCard, {}, {}).attachments.length, 0,
  "a card with neither attachments nor links renders neither, not an error");

const workCardWithLink = {
  id: "w1", owner: "yuki", state: "for_review", title: "A reviewed sprite change",
  links: [{ type: "image", src: "docs/x.png", caption: "Before and after" }],
};
const workRow = queueCtx.qWorkItem(workCardWithLink, {}, "");
assert.equal(workRow.attachments.length, 1, "a work card's media-typed links become evidence the same way");
assert.equal(workRow.attachments[0].caption, "Before and after");

// --- app.js: decisionCard() displays the same images on the direct link ----
const seenAttachments = [];
function control() {
  return { dataset: {}, disabled: false, textContent: "", listeners: {},
    addEventListener(type, fn) { this.listeners[type] = fn; } };
}
function fakeElement(html) {
  const firstRow = { children: [], appendChild(a) { this.children.push(a); }, remove() {}, removed: false };
  const ask = { hidden: false };
  const done = { innerHTML: "", querySelector: () => null };
  const el = {
    html, radios: [], textarea: { value: "", addEventListener() {} }, button: control(), note: { textContent: "" },
    querySelector(selector) {
      return ({ ".d-att-first": firstRow, ".d-thread": null, ".d-ask": ask,
        ".d-done": done, ".d-say": this.textarea, ".d-record": this.button,
        ".d-consequence": this.note })[selector] ?? null;
    },
    querySelectorAll() { return []; },
  };
  el.firstRow = firstRow;
  return el;
}
const appCtx = vm.createContext({
  console, esc: String, md: String, mdi: String,
  h: html => ({ firstElementChild: fakeElement(html) }),
  attachmentEl(a) { seenAttachments.push(a); return { tag: "img", att: a }; },
  cache: {},
});
vm.runInContext(reviewSource, appCtx);
const decisionCardStart = appSource.indexOf("function ruleWhen");
const decisionCardEnd = appSource.indexOf("\n\n/* ---------------- chat", decisionCardStart);
vm.runInContext(appSource.slice(decisionCardStart, decisionCardEnd), appCtx);

const card = appCtx.decisionCard(q122, null, {}, () => {}, {});
assert.equal(seenAttachments.length, 2, "decisionCard hands both image links to the same attachment renderer attachments use");
assert.deepEqual(seenAttachments.map(a => a.caption), ["The rock obstacle", "The fox"]);
assert.equal(card.firstRow.children.length, 2, "the images are appended, not dropped");

console.log("Decision links with a media type render as evidence in both the queue pane and the direct card, and plain reference links still render.");
