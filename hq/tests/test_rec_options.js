// A choice among named options shows every option on his review page
// (2026-10-07: the barn's three looks showed as "C, instead A").
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const ctx = vm.createContext({ routes: {}, location: { hash: '#/' }, mdi: String, esc: String,
  document: { addEventListener() {}, getElementById: () => null } });
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
