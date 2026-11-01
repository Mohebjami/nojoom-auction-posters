const { BrowserWindow, session } = require('electron');
const { parseHTML } = require('linkedom');
const { isNCAPhotoURL } = require('./downloads.cjs');
const { VIN_PATTERN } = require('./workbook.cjs');

const HOME = 'https://my.nca.af/dashboard';
const isNCA = value => {
  try {
    const u = new URL(value);
    return u.origin === 'https://my.nca.af' && !u.username && !u.password;
  } catch { return false; }
};
const isNCAListing = value => isNCA(value) && /^\/inventory\/view\/vehicle\/[\w-]+$/.test(new URL(value).pathname);
const failure = (message, code) => Object.assign(new Error(message), { code });
function component(document, name) {
  for (const element of document.querySelectorAll('[wire\\:snapshot]')) {
    try {
      const snapshot = JSON.parse(element.getAttribute('wire:snapshot'));
      if (snapshot.memo?.name === name) return { element, snapshot };
    } catch {}
  }
  return null;
}
function searchURL(vin) {
  if (!VIN_PATTERN.test(vin || '')) throw new Error('Search requires a complete VIN.');
  const url = new URL(HOME);
  url.searchParams.set('ds', 'false');
  url.searchParams.set('searchTerm', vin);
  return url.href;
}
function parseSearch(html, vin) {
  const { document } = parseHTML(html);
  const page = component(document, 'pages.dashboard.dashboard');
  if (!page || page.snapshot.data.searchTerm !== vin || page.snapshot.data.defaultSearch !== false) {
    throw new Error('NCA did not confirm the VIN search. Retry after signing in.');
  }
  const links = [...new Set([...page.element.querySelectorAll('a[href]')]
    .map(a => { try { return new URL(a.getAttribute('href'), HOME).href; } catch { return ''; } })
    .filter(isNCAListing))];
  if (!links.length && !/\b0\s+Results?\b/i.test(page.snapshot.data.searchResult || '')) {
    throw new Error('NCA returned an unrecognized result list. No vehicles were marked missing.');
  }
  return links;
}
function parseGallery(html, vin, source) {
  if (!isNCAListing(source)) throw new Error('Unsupported NCA vehicle URL.');
  const { document } = parseHTML(html);
  const page = component(document, 'pages.inventory.inventory-vehicle-view');
  if (!page) throw new Error('NCA did not return a vehicle detail page.');
  // Cards show masked VINs. Accept only the full VIN in the vehicle details table.
  const vins = [...page.element.querySelectorAll('tr')].flatMap(row => {
    const cells = [...row.children];
    return cells[0]?.textContent.trim().toUpperCase() === 'VIN' ? [cells[1]?.textContent.trim().toUpperCase()] : [];
  });
  if (vins.length !== 1 || vins[0] !== vin) return null;
  const images = [...new Set([...page.element.querySelectorAll('#carouselExampleInterval a[data-fancybox="gallery"][href]')]
    .map(a => a.getAttribute('href')).filter(isNCAPhotoURL))];
  if (!images.length) throw new Error('The exact NCA VIN has no accessible gallery photos.');
  const imageDescriptions = {};
  for (const anchor of page.element.querySelectorAll('#carouselExampleInterval a[data-fancybox="gallery"][href]')) {
    const url = anchor.getAttribute('href');
    if (!images.includes(url)) continue;
    const img = anchor.querySelector('img');
    imageDescriptions[url] = [imageDescriptions[url], anchor.getAttribute('data-caption'), anchor.getAttribute('title'), img?.getAttribute('alt'), img?.getAttribute('title')].filter(Boolean).join(' ');
  }
  return { source, images, imageDescriptions };
}

class NCABrowser {
  constructor({ runtimePath, onMessage, requestHelp, stopped }) {
    Object.assign(this, { runtimePath, onMessage, requestHelp, stopped });
    this.window = null;
  }
  ensureSession() {
    if (!this.session) {
      this.session = session.fromPath(this.runtimePath);
      this.session.setPermissionRequestHandler((_wc, _permission, callback) => callback(false));
      this.session.setPermissionCheckHandler(() => false);
    }
    return this.session;
  }
  ensureWindow() {
    this.ensureSession();
    if (this.window && !this.window.isDestroyed()) return this.window;
    this.window = new BrowserWindow({
      width: 1120, height: 820, title: 'NCA • Auction Photo Finder', show: false,
      webPreferences: { session: this.session, nodeIntegration: false, contextIsolation: true, sandbox: true, webSecurity: true },
    });
    this.window.setMenuBarVisibility(false);
    this.window.webContents.setWindowOpenHandler(({ url }) => {
      if (isNCA(url)) this.window.loadURL(url).catch(() => {});
      return { action: 'deny' };
    });
    for (const event of ['will-navigate', 'will-redirect']) {
      this.window.webContents.on(event, (e, url) => { if (!isNCA(url)) e.preventDefault(); });
    }
    this.window.on('page-title-updated', event => event.preventDefault());
    return this.window;
  }
  checkStopped() {
    if (this.stopped()) throw failure('Stopped', 'STOPPED');
    this.signal?.throwIfAborted();
  }
  requestSignal(signal) {
    return AbortSignal.any([signal, this.signal, AbortSignal.timeout(45000)].filter(Boolean));
  }
  async fetchPage(url) {
    if (!isNCA(url)) throw new Error('Only NCA pages can be searched.');
    this.checkStopped();
    const response = await this.ensureSession().fetch(url, { signal: this.requestSignal(), redirect: 'manual' });
    if ([301, 302, 303, 307, 308].includes(response.status)) {
      const target = new URL(response.headers.get('location') || '/', url);
      if (isNCA(target.href) && target.pathname === '/login') throw failure('Sign in to NCA before searching.', 'NCA_LOGIN');
      throw new Error('NCA redirected the search unexpectedly. Open its browser and retry.');
    }
    if ([401, 419].includes(response.status)) throw failure('Your NCA session expired. Sign in again.', 'NCA_LOGIN');
    if (!response.ok) throw new Error(`NCA returned HTTP ${response.status}. Retry later.`);
    const html = await response.text();
    if (/wire:submit="login"/.test(html)) throw failure('Sign in to NCA before searching.', 'NCA_LOGIN');
    return html;
  }
  async login(email, password) {
    if (typeof email !== 'string' || typeof password !== 'string' || !email.trim() || !password || email.length > 254 || password.length > 1024) {
      throw new Error('Enter your NCA email and password.');
    }
    const response = await this.ensureSession().fetch('https://my.nca.af/login', { signal: this.requestSignal(), redirect: 'manual' });
    // An already authenticated account may redirect away from the login form.
    if (response.status === 302 && new URL(response.headers.get('location'), HOME).href === HOME) {
      await this.fetchPage(HOME);
      return;
    }
    if (!response.ok) throw new Error(`NCA login returned HTTP ${response.status}.`);
    const { document } = parseHTML(await response.text());
    const page = component(document, 'pages.auth.login');
    const token = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content');
    if (!page || !token) throw new Error('NCA login form changed. Sign in using the NCA browser.');
    const result = await this.session.fetch('https://my.nca.af/livewire/update', {
      method: 'POST', redirect: 'error', signal: this.requestSignal(),
      headers: { 'Content-Type': 'application/json', Accept: 'application/json', 'X-Livewire': '' },
      body: JSON.stringify({ _token: token, components: [{
        snapshot: page.element.getAttribute('wire:snapshot'),
        updates: { 'form.email': email.trim(), 'form.password': password, 'form.remember': false },
        calls: [{ path: '', method: 'login', params: [] }],
      }] }),
    });
    if (!result.ok) throw new Error(`NCA sign-in returned HTTP ${result.status}.`);
    const data = await result.json();
    const redirect = data.components?.[0]?.effects?.redirect;
    if (!redirect || new URL(redirect, HOME).href !== HOME) throw new Error('NCA sign-in failed. Check your email and password, or use the NCA browser.');
    await this.fetchPage(HOME);
    await this.session.cookies.flushStore();
    this.onMessage('Signed in to NCA. Ready to search vehicle photos.');
  }
  async authenticatedPage(url) {
    try { return await this.fetchPage(url); }
    catch (error) {
      if (error.code !== 'NCA_LOGIN') throw error;
      await this.open();
      await this.requestHelp('NCA needs you to sign in. Complete login in the NCA browser, then click Continue here.');
      this.checkStopped();
      return this.fetchPage(url);
    }
  }
  async lookup(vin) {
    this.onMessage(`Searching NCA for ${vin}…`);
    const links = parseSearch(await this.authenticatedPage(searchURL(vin)), vin);
    for (const source of links) {
      const listing = parseGallery(await this.authenticatedPage(source), vin, source);
      if (listing) return listing;
    }
    throw failure('No exact VIN match was found on NCA.', 'NOT_FOUND');
  }
  async fetchPhoto(url, signal) {
    if (!isNCAPhotoURL(url)) throw new Error('Unsupported NCA photo host.');
    this.checkStopped();
    return this.ensureSession().fetch(url, { signal: this.requestSignal(signal), redirect: 'error', headers: { Accept: 'image/*' } });
  }
  async load(url) {
    if (!isNCA(url)) throw new Error('Unsupported NCA page.');
    await this.ensureWindow().loadURL(url);
  }
  async open() {
    this.ensureWindow().show();
    if (!isNCA(this.window.webContents.getURL())) await this.load(HOME);
  }
  stopNavigation() {
    if (this.window && !this.window.isDestroyed()) this.window.webContents.stop();
  }
}

module.exports = { NCABrowser, HOME, isNCA, isNCAListing, searchURL, parseSearch, parseGallery };
