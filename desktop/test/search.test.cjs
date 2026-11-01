const { test } = require('node:test');
const assert = require('node:assert/strict');
const { searchURL, parseSearch } = require('../photo-finder/search.cjs');
const { BidCarsBrowser } = require('../photo-finder/bidcars.cjs');
const VIN = 'JTDKN3DU5B0249292';
const OTHER = 'JTEZU17R868042363';
const record = { vin: VIN, lot: '1-73097295', tag: `2011-Toyota-Prius-${VIN}`,
  img: { img_1: 'https://mercury.bid.cars/thumb.jpg' },
  img_large: { img_1: 'https://pluto.bid.car/photo1.jpg', img_2: 'https://pluto.bid.car/photo2.jpg' } };
function browser() {
  const b = new BidCarsBrowser({ runtimePath: '/unused', onMessage: () => {}, requestHelp: () => { throw new Error('Should not require manual search'); }, stopped: () => false });
  b.window = { isDestroyed: () => false };
  b.ensureWindow = () => b.window;
  return b;
}
test('uses the real typing query route, carrying the full VIN in both auction states', () => {
  for (const archived of [true, false]) {
    for (const api of [true, false]) {
      const url = new URL(searchURL(VIN, archived, api));
      assert.equal(url.searchParams.get('query'), VIN);
      assert.equal(url.searchParams.get('search-type'), 'typing');
      assert.equal(url.pathname, `/${api ? 'app' : 'en'}/search/${archived ? 'archived/' : ''}${api ? 'request' : 'results'}`);
    }
  }
  assert.throws(() => searchURL('bad', true), /complete VIN/);
});
test('structured VIN match selects full-size gallery images and skips similar vehicles', () => {
  const listing = parseSearch({ data: [{ ...record, vin: OTHER }, record] }, VIN, true);
  assert.deepEqual(listing.images, Object.values(record.img_large));
  assert.equal(new URL(listing.source).searchParams.get('archived'), 'true');
  assert.equal(parseSearch({ data: [{ ...record, vin: OTHER }] }, VIN, false), null);
});
test('rejects malformed search data, mismatched listing URLs, and foreign image hosts', () => {
  assert.throws(() => parseSearch({}, VIN, true), /unexpected search response/);
  assert.throws(() => parseSearch({ data: [{ ...record, tag: `2011-Prius-${OTHER}` }] }, VIN, true), /valid vehicle listing URL/);
  const listing = parseSearch({ data: [{ ...record, img_large: { img_1: 'https://evil.example/car.jpg' } }] }, VIN, false);
  assert.deepEqual(listing.images, []);
});
test('automatic lookup uses the exact-VIN response without opening a page or asking for manual search', async () => {
  const b = browser();
  b.search = async () => ({ data: [record] });
  b.load = () => { throw new Error('Should not open the homepage'); };
  const listing = await b.lookup(VIN);
  assert.deepEqual(listing.images, Object.values(record.img_large));
});
test('falls back from archived to current, then reports missing vehicles without stalling', async () => {
  const b = browser(); const calls = [];
  b.search = async (_vin, archived) => { calls.push(archived); return { data: archived ? [] : [record] }; };
  assert.equal((await b.lookup(VIN)).images.length, 2);
  assert.deepEqual(calls, [true, false]);
  b.search = async () => ({ data: [] });
  await assert.rejects(b.lookup(VIN), error => error.code === 'NOT_FOUND');
});
test('browser verification fallback loads the actual VIN results URL before retrying the request', async () => {
  const b = browser(); let calls = 0; let loaded;
  b.search = async () => { if (calls++ === 0) { const e = new Error('Verification'); e.code = 'SEARCH_ACCESS'; throw e; } return { data: [record] }; };
  b.load = async (url, vin) => { loaded = { url, vin }; };
  assert.equal((await b.lookup(VIN)).images.length, 2);
  assert.equal(new URL(loaded.url).searchParams.get('query'), VIN);
  assert.equal(loaded.vin, VIN);
});
test('network search is aborted when Stop batch is pressed', async () => {
  const b = browser(); const c = new AbortController(); b.signal = c.signal;
  b.session = { fetch: async (_url, options) => { c.abort(); options.signal.throwIfAborted(); } };
  await assert.rejects(b.search(VIN, true), /abort/i);
});
test('photo requests do not inject a cross-origin Referer rejected by Chromium', async () => {
  const b = browser(); let options;
  b.session = { fetch: async (_url, value) => { options = value; return new Response('photo'); } };
  await b.fetchPhoto('https://pluto.bid.car/photo.jpg');
  assert.equal(new Headers(options.headers).has('referer'), false);
});
test('Skip vehicle during browser verification is propagated instead of swallowed', async () => {
  const b = browser();
  b.snapshot = async () => ({ blocked: true });
  b.help = async () => { const error = new Error('Skipped'); error.code = 'SKIPPED'; throw error; };
  await assert.rejects(b.waitUntilReady(VIN), error => error.code === 'SKIPPED');
});
