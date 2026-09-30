// Opening a review artifact must not navigate away from the card being reviewed:
// a picture opens in the full-size viewer over the page, anything else in a new tab.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

let clickListener, shown;
const ctx = vm.createContext({
  esc: String,
  reviewEvidenceLinks: item => item.deliverable.evidence.map(e => ({ href: e.path, label: e.label || e.path })),
  showFullSize: (...args) => { shown = args; },
  document: { addEventListener(type, listener) { if (type === 'click') clickListener = listener; } },
});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../static/review_evidence.js'), 'utf8'), ctx);

const html = ctx.reviewComparison({ deliverable: { evidence: [
  { path: '/docs/sheet.png', label: 'Sheet' },
  { path: '/docs/clip.mp4', label: 'Clip' },
  { path: '/docs/notes.md', label: 'Notes' },
] } });
const links = [...html.matchAll(/<a [^>]*>[^<]*<\/a>/g)].map(m => m[0]);
const open = name => links.find(a => a.includes(name));

assert.match(open('href="/docs/sheet.png"'), /data-review-full/);
assert.doesNotMatch(open('href="/docs/sheet.png"'), /target=/);
assert.match(open('href="/docs/clip.mp4"'), /target="_blank"/);
assert.match(open('href="/docs/notes.md"'), /target="_blank"/);
assert.match(ctx.reviewHeadingArtifact({ deliverable: { evidence: [{ path: '/docs/sheet.png' }] } }), /data-review-full/);

const link = { getAttribute: name => name === 'href' ? '/docs/sheet.png' : null, dataset: { reviewCaption: 'Sheet' } };
let prevented = false;
const click = extra => ({ target: { closest: () => link }, button: 0, preventDefault() { prevented = true; }, ...extra });

clickListener(click({ ctrlKey: true }));
assert.equal(prevented, false, 'a modified click still opens the file in a new tab');
assert.equal(shown, undefined);

clickListener(click({}));
assert.equal(prevented, true, 'a plain click stays on the page');
assert.deepEqual([...shown], ['/docs/sheet.png', 'Sheet', true]);

console.log('ok   review artifacts open in place');
