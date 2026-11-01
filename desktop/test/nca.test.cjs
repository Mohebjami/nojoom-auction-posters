const { test } = require('node:test');
const assert = require('node:assert/strict');
const { NCABrowser, isNCA, isNCAListing, searchURL, parseSearch, parseGallery } = require('../photo-finder/nca.cjs');
const { isNCAPhotoURL, isBidCarsPhotoURL, isPhotoURL } = require('../photo-finder/downloads.cjs');
const { lookupSources } = require('../photo-finder/sources.cjs');
const VIN = 'JTEZU17R868042363';
const OTHER = 'JTDKN3DU2A0090987';
const SOURCE = 'https://my.nca.af/inventory/view/vehicle/vn5-O1Kly3lKHahn3tyx5Q?lot=50003';
const PHOTO = 'https://nap.fsn1.your-objectstorage.com/noewarid/file-manager/vehicles/3/photo.jpg';
function component(name, data, content) {
  const snapshot = JSON.stringify({ memo: { name }, data }).replace(/&/g, '&amp;').replace(/"/g, '&quot;');
  return `<div wire:snapshot="${snapshot}">${content}</div>`;
}
const gallery = (vin = VIN) => component('pages.inventory.inventory-vehicle-view', {}, `
  <table><tr><td>VIN</td><th>${vin}</th></tr></table>
  <div id="carouselExampleInterval"><a href="${PHOTO}" data-fancybox="gallery"><img src="${PHOTO}"></a>
  <a href="${PHOTO}" data-fancybox="gallery">Duplicate</a>
  <a href="https://evil.example/photo.jpg" data-fancybox="gallery">Untrusted</a></div>
  <img src="https://my.nca.af/logo.png"><a href="${PHOTO.replace('photo', 'related')}" data-fancybox="gallery">Related</a>`);
const missing = () => Object.assign(new Error('No match'), { code: 'NOT_FOUND' });
function browser() {
  return new NCABrowser({ runtimePath: '/unused', onMessage: () => {}, requestHelp: async () => {}, stopped: () => false });
}
test('NCA search carries the full VIN and disables the default grouped view', () => {
  const url = new URL(searchURL(VIN));
  assert.equal(url.pathname, '/dashboard');
  assert.equal(url.searchParams.get('searchTerm'), VIN);
  assert.equal(url.searchParams.get('ds'), 'false');
  assert.throws(() => searchURL('JTEZU17R868*'), /complete VIN/);
});
test('NCA uses only its own pages and the observed vehicle image storage path', () => {
  assert.equal(isNCA(SOURCE), true);
  assert.equal(isNCAListing(SOURCE), true);
  assert.equal(isNCAPhotoURL(PHOTO), true);
  assert.equal(isPhotoURL(PHOTO), true);
  assert.equal(isBidCarsPhotoURL(PHOTO), false);
  for (const url of ['http://my.nca.af/dashboard', 'https://user@my.nca.af/dashboard', 'https://my.nca.af.evil.example/dashboard']) assert.equal(isNCA(url), false);
  assert.equal(isNCAListing('https://my.nca.af/inventory/modify/vehicle/123'), false);
  for (const url of [PHOTO.replace('https:', 'http:'), PHOTO.replace('/vehicles/', '/users/'), PHOTO.replace('nap.fsn1.', 'other.'), PHOTO.replace('/3/', '/'), PHOTO.replace('photo.jpg', 'file.pdf'), PHOTO.replace('https://', 'https://user@')]) assert.equal(isNCAPhotoURL(url), false);
});
test('NCA accepts only links within the confirmed VIN search component', () => {
  const html = `<a href="${SOURCE.replace('50003', '99999')}">Outside results</a>` +
    component('pages.dashboard.dashboard', { searchTerm: VIN, defaultSearch: false }, `<a href="${SOURCE}">Masked VIN</a><a href="${SOURCE}">Duplicate</a><a href="https://evil.example/inventory/view/vehicle/id">Wrong host</a>`);
  assert.deepEqual(parseSearch(html, VIN), [SOURCE]);
  assert.throws(() => parseSearch(html, OTHER), /did not confirm/);
  assert.throws(() => parseSearch('<h1>Sign in</h1>', VIN), /did not confirm/);
  assert.deepEqual(parseSearch(component('pages.dashboard.dashboard', { searchTerm: VIN, defaultSearch: false, searchResult: '<i></i> 0 Result' }, ''), VIN), []);
  assert.throws(() => parseSearch(component('pages.dashboard.dashboard', { searchTerm: VIN, defaultSearch: false, searchResult: '<i></i> 1 Result' }, ''), VIN), /unrecognized result list/);
});
test('NCA verifies the full detail-table VIN and uses only primary carousel photos', () => {
  assert.deepEqual(parseGallery(gallery(), VIN, SOURCE), { source: SOURCE, images: [PHOTO], imageDescriptions: { [PHOTO]: '' } });
  assert.equal(parseGallery(gallery(OTHER), VIN, SOURCE), null);
  assert.equal(parseGallery(gallery('JTEZU17R868*'), VIN, SOURCE), null);
  assert.throws(() => parseGallery(gallery(), VIN, 'https://evil.example/vehicle/1'), /Unsupported/);
  assert.throws(() => parseGallery(component('pages.inventory.inventory-vehicle-view', {}, `<table><tr><td>VIN</td><th>${VIN}</th></tr></table>`), VIN, SOURCE), /no accessible gallery/);
});
test('NCA lookup rejects mismatched candidates before returning an exact gallery', async () => {
  const b = browser(); const otherSource = SOURCE.replace('vn5-O1Kly3lKHahn3tyx5Q', 'other');
  b.authenticatedPage = async url => url.includes('searchTerm=')
    ? component('pages.dashboard.dashboard', { searchTerm: VIN, defaultSearch: false }, `<a href="${otherSource}">Other</a><a href="${SOURCE}">Exact</a>`)
    : gallery(url === otherSource ? OTHER : VIN);
  assert.equal((await b.lookup(VIN)).source, SOURCE);
});
test('NCA authentication expiry opens login and requires a successful retry', async () => {
  const b = browser(); let opened = 0; let helped = 0; let requests = 0;
  b.session = { fetch: async () => ++requests === 1 ? new Response('', { status: 302, headers: { location: '/login' } }) : new Response('Vehicle page') };
  b.open = async () => { opened++; };
  b.requestHelp = async () => { helped++; };
  assert.equal(await b.authenticatedPage(SOURCE), 'Vehicle page');
  assert.equal(opened, 1); assert.equal(helped, 1);
  b.session.fetch = async () => new Response('', { status: 302, headers: { location: '/login' } });
  await assert.rejects(b.authenticatedPage(SOURCE), e => e.code === 'NCA_LOGIN');
});
test('NCA login posts credentials only to its login action with the current CSRF snapshot', async () => {
  const b = browser(); let posted; let flushed = false;
  b.session = { cookies: { flushStore: async () => { flushed = true; } }, fetch: async (url, options) => {
    if (url.endsWith('/login')) return new Response('<meta name="csrf-token" content="test-token">' + component('pages.auth.login', {}, '<form wire:submit="login"></form>'));
    if (url.endsWith('/livewire/update')) { posted = { url, body: JSON.parse(options.body) }; return Response.json({ components: [{ effects: { redirect: '/dashboard' } }] }); }
    return new Response('Dashboard');
  } };
  await b.login('test@example.com', 'test-password');
  assert.equal(posted.url, 'https://my.nca.af/livewire/update');
  assert.equal(posted.body._token, 'test-token');
  assert.deepEqual(posted.body.components[0].updates, { 'form.email': 'test@example.com', 'form.password': 'test-password', 'form.remember': false });
  assert.deepEqual(posted.body.components[0].calls, [{ path: '', method: 'login', params: [] }]);
  assert.equal(flushed, true);
  assert.equal(JSON.stringify(b).includes('test-password'), false);
});
test('NCA rejects invalid login responses without echoing submitted credentials', async () => {
  const b = browser();
  b.session = { fetch: async url => url.endsWith('/login') ? new Response('<meta name="csrf-token" content="token">' + component('pages.auth.login', {}, '')) : Response.json({ components: [{ effects: {} }] }) };
  await assert.rejects(b.login('test@example.com', 'secret'), /sign-in failed/);
});
test('NCA page and photo requests abort promptly and reject unapproved redirects', async () => {
  const b = browser(); const c = new AbortController(); b.signal = c.signal;
  b.session = { fetch: async (_url, options) => { c.abort(); options.signal.throwIfAborted(); } };
  await assert.rejects(b.fetchPage(SOURCE), /abort/i);
  await assert.rejects(b.fetchPhoto(PHOTO), /abort/i);
  await assert.rejects(browser().fetchPhoto('https://evil.example/a.jpg'), /Unsupported/);
  const redirect = browser(); redirect.session = { fetch: async () => new Response('', { status: 302, headers: { location: 'https://evil.example/login' } }) };
  await assert.rejects(redirect.fetchPage(SOURCE), /unexpectedly/);
});
test('combined lookup falls back to NCA and retains the correct downloader', async () => {
  const calls = [];
  const browsers = { bidcars: { lookup: async () => { calls.push('bidcars'); throw missing(); } }, nca: { lookup: async () => { calls.push('nca'); return { source: SOURCE, images: [PHOTO] }; } } };
  assert.equal((await lookupSources(browsers, 'both', VIN)).provider, 'nca');
  assert.deepEqual(calls, ['bidcars', 'nca']);
  calls.length = 0;
  await lookupSources(browsers, 'nca', VIN);
  assert.deepEqual(calls, ['nca']);
});
test('combined lookup distinguishes no matches from access failures and propagates Skip and Stop', async () => {
  const browsers = { bidcars: { lookup: async () => { throw missing(); } }, nca: { lookup: async () => { throw missing(); } } };
  await assert.rejects(lookupSources(browsers, 'both', VIN), e => e.code === 'NOT_FOUND');
  browsers.nca.lookup = async () => { throw new Error('Sign in required'); };
  await assert.rejects(lookupSources(browsers, 'both', VIN), e => e.code !== 'NOT_FOUND' && /Sign in required/.test(e.message));
  browsers.bidcars.lookup = async () => { throw Object.assign(new Error('Skip'), { code: 'SKIPPED' }); };
  await assert.rejects(lookupSources(browsers, 'both', VIN), e => e.code === 'SKIPPED');
  const c = new AbortController(); c.abort();
  await assert.rejects(lookupSources(browsers, 'both', VIN, c.signal), /abort/i);
});
