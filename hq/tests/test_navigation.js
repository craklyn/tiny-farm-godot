// Navigation destinations, switchboard transitions and layout selection.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const root = path.join(__dirname, '../static');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const app = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const surface = JSON.parse(fs.readFileSync(path.join(__dirname, '../data/surface.json'), 'utf8'));
const primary = [...html.matchAll(/<a [^>]*href="([^"]+)" data-section="([^"]+)"/g)];
assert.deepEqual(primary.map(([, href, section]) => [section, href]), [
  ['overview', '#/'], ['decisions', '#/work'], ['work', '#/work-status'],
  ['studio', '#/design'], ['request', '#/request'],
]);
for (const route of ['/org', '/program', '/maps', '/chat']) {
  assert.ok(html.includes(`data-route="${route}"`));
  assert.ok(!primary.some(([, href]) => href === `#${route}`));
}
assert.ok(html.includes('id="work-badge"'), 'Decisions retains the shared ready count');
assert.ok(html.includes('id="nav-pillars-exc"'), 'Pillar status remains reachable');
assert.ok(html.includes('id="nav-pillars"'));
const links = [...html.matchAll(/<a href="#([^"]+)" data-route="([^"]+)"/g)]
  .map(([, href, route]) => ({ href, dataset: { route }, hidden: false, title: '',
    classList: { remove() {} }, removeAttribute() {} }));
const primaryLinks = primary.map(([, href, section]) => ({ href, dataset: { section }, hidden: false,
  getAttribute: () => href }));
const classes = new Set();
const toggle = { textContent: '', attributes: {}, setAttribute(key, value) { this.attributes[key] = value; },
  addEventListener(type, handler) { this.click = handler; } };
const saved = {};
const document = { querySelectorAll: selector => selector.startsWith('#sidebar') ? []
    : selector.startsWith('.primary-nav') ? primaryLinks : links,
  getElementById: () => toggle,
  body: { classList: { toggle(name, on) { if (on) classes.add(name); else classes.delete(name); },
    contains: name => classes.has(name) } } };
const localStorage = { getItem: key => saved[key] || null, setItem: (key, value) => { saved[key] = value; } };
const ctx = vm.createContext({ document, localStorage, surfaceCfg: surface });
const code = app.slice(app.indexOf('function navSection('), app.indexOf('async function route()', app.indexOf('function navSection(')));
vm.runInContext(code, ctx);
ctx.surfaceParked = route => ctx.surfaceCfg.parked[String(route).replace(/^#/, '')] || null;
ctx.syncNavAvailability();
for (const route of ['/org', '/program', '/maps', '/chat'])
  assert.equal(links.find(link => link.dataset.route === route).hidden, true, `${route} parked`);
assert.equal(links.find(link => link.dataset.route === '/program/goals').hidden, false);
delete ctx.surfaceCfg.parked['/maps'];
ctx.syncNavAvailability();
assert.equal(links.find(link => link.dataset.route === '/maps').hidden, false, 'restored route reappears');
ctx.surfaceCfg.parked['/design'] = { exact: true };
ctx.syncNavAvailability();
assert.equal(primaryLinks.find(link => link.dataset.section === 'studio').hidden, true);
delete ctx.surfaceCfg.parked['/design'];
ctx.syncNavAvailability();
assert.equal(primaryLinks.find(link => link.dataset.section === 'studio').hidden, false,
  'restored primary route returns to its normal place');
assert.equal(ctx.navSection('/inbox/Q-1'), 'decisions');
assert.equal(ctx.navSection('/work/w123'), 'work');
assert.equal(ctx.navSection('/request/w123'), 'request');
assert.equal(ctx.navSection('/work-status'), 'work');
assert.equal(ctx.navSection('/sprite/creatures/crow'), 'studio');
assert.equal(ctx.navSection('/pillar/product'), 'overview');

assert.ok(html.includes('id="nav-layout-toggle"'));
assert.ok(html.includes('/static/work_status.js'));
assert.ok(html.includes('/static/request.js'));
ctx.initNavLayout();
assert.equal(toggle.textContent, 'Try compact sidebar');
toggle.click();
assert.equal(saved['hq-nav-layout'], 'sidebar');
assert.equal(toggle.textContent, 'Try top bar');
assert.equal(toggle.attributes['aria-pressed'], 'true');
ctx.initNavLayout(); // simulate script setup after a reload using persisted preference
assert.equal(toggle.textContent, 'Try top bar');
toggle.click();
assert.equal(saved['hq-nav-layout'], 'top');
ctx.initNavLayout();
toggle.click();
assert.equal(saved['hq-nav-layout'], 'sidebar');
console.log('Navigation routes, parked tools, and layout switching pass.');

// Exercise the real router: action queries must not override Work's parser.
const work = fs.readFileSync(path.join(root, 'work.js'), 'utf8');
vm.runInContext(work.slice(work.indexOf('function workFocusId()'),
  work.indexOf('function advanceDirectDecision(')), ctx);
const landings = [];
Object.assign(ctx, {
  clearAnimators() {}, hidePersonTip() {}, applyNavGroups() {}, routeSeq: 0, routeActive: 0,
  location: { hash: '' }, $view: { innerHTML: '' }, surfaceReady: Promise.resolve(),
  routes: {}, h: String, esc: String, surfaceMarkLinks() {},
  renderWork(focusId = ctx.workFocusId()) {
    landings.push([focusId, ctx.workActionId()]);
  },
});
vm.runInContext(app.slice(app.indexOf('async function route()'),
  app.indexOf('window.addEventListener("hashchange", route)')), ctx);
(async () => {
  const id = 'w1096c1cd319', action = 'act_3f648036f1c057d2721e';
  for (const prefix of ['/work/', '/inbox/']) {
    ctx.location.hash = '#' + prefix + id + '?action=' + action;
    await ctx.route();
    assert.deepEqual(landings.pop(), [id, action], 'card and action are separate');
    ctx.location.hash = '#' + prefix + 'Q%2D123';
    await ctx.route();
    assert.deepEqual(landings.pop(), ['Q-123', ''], 'plain links decode their card ID');
  }
  console.log('Work and inbox links preserve card IDs and action queries.');
})().catch(error => { console.error(error); process.exitCode = 1; });
