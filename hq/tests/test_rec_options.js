// A choice among named options shows every option on his review page
// (2026-10-07: the barn's three looks showed as "C, instead A").
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const ctx = vm.createContext({ routes: {}, location: { hash: '#/' }, mdi: String, esc: String,
  document: { addEventListener() {}, getElementById: () => null } });
vm.runInContext(fs.readFileSync(path.join(__dirname, '../static/review_evidence.js'), 'utf8'), ctx);
vm.runInContext(fs.readFileSync(path.join(__dirname, '../static/queue.js'), 'utf8'), ctx);
const html = ctx.recOptionsHtml([
  { label: 'A. Red dairy works', summary: 'A red timber barn.' },
  { label: 'B. Blue-and-cream creamery', summary: 'Pale masonry and tile.' },
  { label: 'C. Pine visitor gallery', summary: 'Pine gallery over the steel line.' }]);
for (const label of ['A. Red dairy works', 'B. Blue-and-cream creamery', 'C. Pine visitor gallery'])
  assert.ok(html.includes(label), `${label} is on the page`);
assert.ok(html.includes('Pale masonry and tile.'), 'each option says what choosing it means');
assert.equal(ctx.recOptionsHtml([]), '', 'no options, no list');
assert.equal(ctx.recOptionsHtml([{ label: 'Only one' }]), '', 'one option is not a choice');
console.log('ok — every option of a choice is shown');

// The row a work card becomes keeps them too. A work row also carries an empty
// `options` for decision buttons, which once overwrote these (2026-10-07).
Object.assign(ctx, { reviewTitle: () => '', reviewEvidenceLinks: () => [], ownerOf: () => ({ name: 'Milo Fern' }), followUps: card => card.follow_ups || [],
  qFirst: name => String(name).split(' ')[0] });
const card = { id: 'wd47fae82082', title: 'Write the barn proposal', owner: 'milo', state: 'for_review', tier: 1,
  recommend: { question: 'Which look?', answer: 'Choose C.', why: 'Warm.', instead: 'A or B.', options: [
    { label: 'A. Red dairy works', summary: 'Red timber.' }, { label: 'B. Blue-and-cream creamery', summary: 'Tile.' },
    { label: 'C. Pine visitor gallery', summary: 'Pine and glass.' }] } };
const row = ctx.qWorkItem(card, { employees: [] }, '');
assert.equal(row.recOptions.length, 3, 'the work row keeps all three options');
assert.equal(row.options.length, 0, 'decision buttons stay empty on a work row');
console.log('ok — the work row carries every option');

// A reply that started work says so, with a link, so the page never implies the
// work waits on his yes (2026-10-07: the prototypes were filed by Milo's reply,
// but the page showed only the accept button).
const replied = ctx.qWorkItem({ ...card, conversation: [
  { role: 'daniel', text: 'Please generate prototypes.' },
  { role: 'milo', text: 'Design art first.', filed: [{ id: 'we8c970ceca6', title: 'Render three prototypes', owner: 'yuki' }] }] },
  { employees: [] }, '');
assert.equal(replied.conversation[1].filed[0].id, 'we8c970ceca6', 'the started card travels with the reply');
console.log('ok — a reply that started work carries it');
