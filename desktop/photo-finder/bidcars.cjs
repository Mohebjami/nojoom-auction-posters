const { BrowserWindow, session } = require('electron');
const { inspectPage, callScript } = require('./page-scripts.cjs');
const { isBidCarsPhotoURL: isPhotoURL } = require('./downloads.cjs');
const { searchURL, parseSearch } = require('./search.cjs');

const HOME = 'https://bid.cars/en/bidcar';
const isBidCars = value => {
  try { const u = new URL(value); return u.protocol === 'https:' && ['bid.cars', 'www.bid.cars'].includes(u.hostname); }
  catch { return false; }
};

class BidCarsBrowser {
  constructor({ runtimePath, onMessage, requestHelp, stopped }) {
    this.runtimePath = runtimePath;
    this.onMessage = onMessage;
    this.requestHelp = requestHelp;
    this.stopped = stopped;
    this.window = null;
  }
  ensureWindow() {
    if (this.window && !this.window.isDestroyed()) return this.window;
    this.session = session.fromPath(this.runtimePath);
    this.session.setPermissionRequestHandler((_wc, _permission, callback) => callback(false));
    this.session.setPermissionCheckHandler(() => false);
    this.window = new BrowserWindow({
      width: 1120, height: 820, title: 'Bid.Cars • Auction Photo Finder', show: false,
      webPreferences: { session: this.session, nodeIntegration: false, contextIsolation: true, sandbox: true, webSecurity: true, backgroundThrottling: false },
    });
    this.window.setMenuBarVisibility(false);
    this.window.webContents.setWindowOpenHandler(({ url }) => {
      if (isBidCars(url)) this.window.loadURL(url).catch(() => {});
      return { action: 'deny' };
    });
    this.window.webContents.on('will-navigate', (event, url) => { if (!isBidCars(url)) event.preventDefault(); });
    this.window.on('page-title-updated', event => event.preventDefault());
    return this.window;
  }
  checkStopped() {
    if (this.stopped()) throw new Error('Stopped');
    if (!this.window || this.window.isDestroyed()) throw new Error('The Bid.Cars browser was closed. Open it again and retry.');
  }
  async delay(ms) {
    for (let remaining = ms; remaining > 0; remaining -= 150) {
      this.checkStopped();
      await new Promise(resolve => setTimeout(resolve, Math.min(150, remaining)));
    }
  }
  async load(url, vin = '') {
    if (!isBidCars(url)) throw new Error('Only Bid.Cars pages can be searched.');
    this.ensureWindow();
    await Promise.race([
      this.window.loadURL(url).catch(error => {
        // Cloudflare may initially return a non-2xx document which still renders.
        if (!String(error.message).includes('ERR_HTTP_RESPONSE_CODE_FAILURE')) throw error;
      }),
      new Promise((_, reject) => { const t = setTimeout(() => reject(new Error('Bid.Cars took too long to load. Retry when your connection is ready.')), 45000); t.unref(); }),
    ]);
    return this.waitUntilReady(vin);
  }
  async snapshot(vin = '') {
    this.checkStopped();
    if (!isBidCars(this.window.webContents.getURL())) throw new Error('The browser is outside Bid.Cars.');
    return this.window.webContents.executeJavaScript(callScript(inspectPage, vin));
  }
  async waitUntilReady(vin = '') {
    for (let attempt = 0; attempt < 25; attempt++) {
      this.checkStopped();
      let page;
      try {
        page = await this.snapshot(vin);
      } catch (error) {
        if (this.stopped() || !this.window || this.window.isDestroyed()) throw error;
        await this.delay(300);
        continue;
      }
      if (page.blocked) {
        await this.help('Bid.Cars needs browser verification. Complete it in the Bid.Cars window, then click Continue here.');
        continue;
      }
      if (page.inputs.some(i => /vin/i.test(`${i.placeholder} ${i.name}`)) || page.verified || page.links.length || page.noResults) return page;
      await this.delay(300);
    }
    throw new Error('Bid.Cars did not load its search or vehicle details. Please retry this vehicle.');
  }
  async help(message) {
    this.checkStopped();
    this.window.show();
    await this.requestHelp(message);
    this.checkStopped();
  }
  async open() {
    this.ensureWindow();
    this.window.show();
    if (!isBidCars(this.window.webContents.getURL())) await this.window.loadURL(HOME);
  }
  async lookup(vin) {
    this.ensureWindow();
    for (const archived of [true, false]) {
      this.onMessage(`Searching ${archived ? 'archived' : 'current'} auctions for ${vin}…`);
      let payload;
      try { payload = await this.search(vin, archived); }
      catch (error) {
        if (error.code !== 'SEARCH_ACCESS') throw error;
        // A real browser session can establish the site's ordinary verification cookies.
        // Do not submit the homepage's action="#" form: it drops the unnamed VIN input.
        await this.load(searchURL(vin, archived), vin);
        payload = await this.search(vin, archived);
      }
      this.checkStopped();
      const listing = parseSearch(payload, vin, archived);
      if (!listing) continue;
      if (listing.images.length) return listing;
      await this.load(listing.source, vin);
      return this.gallery(vin);
    }
    const error = new Error('No exact VIN match was found in the current or archived search results.');
    error.code = 'NOT_FOUND';
    throw error;
  }
  async search(vin, archived) {
    this.checkStopped();
    const response = await this.session.fetch(searchURL(vin, archived, true), {
      signal: this.requestSignal(), redirect: 'error',
      headers: { Accept: 'application/json, text/javascript, */*; q=0.01',
        'X-Requested-With': 'XMLHttpRequest' },
    });
    if (response.status === 429) throw new Error('Bid.Cars is limiting requests. Wait a few minutes, then retry unfinished vehicles.');
    const text = await response.text();
    if ([401, 403].includes(response.status) || /^\s*</.test(text)) {
      const error = new Error('Bid.Cars requires a browser session before it will return search results.');
      error.code = 'SEARCH_ACCESS'; throw error;
    }
    if (!response.ok) throw new Error(`Bid.Cars search returned HTTP ${response.status}.`);
    try { return JSON.parse(text); } catch { throw new Error('Bid.Cars returned invalid search data. Please retry.'); }
  }
  requestSignal(signal) {
    return AbortSignal.any([signal, this.signal, AbortSignal.timeout(40000)].filter(Boolean));
  }
  async gallery(vin) {
    let best = [];
    let stable = 0;
    let page;
    for (let i = 0; i < 24; i++) {
      page = await this.snapshot(vin);
      if (page.blocked) { await this.help('Complete browser verification, then click Continue.'); continue; }
      if (!page.verified) {
        await this.delay(350);
        continue;
      }
      if (page.images.length > best.length) { best = page.images; stable = 0; }
      else if (best.length) stable++;
      if (stable >= 4) break;
      await this.delay(400);
    }
    if (!page?.verified) throw new Error('The vehicle page did not confirm the exact VIN. No photos were saved.');
    const images = best.filter(isPhotoURL);
    if (!images.length) throw new Error('This VIN page has no accessible gallery photos. Photos may be unavailable or the website layout may have changed.');
    return { source: page.url, images };
  }
  async fetchPhoto(url, signal) {
    if (!isPhotoURL(url)) throw new Error('Unsupported photo host.');
    const combined = this.requestSignal(signal);
    return this.session.fetch(url, {
      signal: combined, redirect: 'error',
      // Electron's session fetch has no document referrer. Manually adding a full
      // cross-origin Referer makes Chromium reject the request before it is sent.
      headers: { Accept: 'image/avif,image/webp,image/*,*/*;q=0.8' },
    });
  }
  stopNavigation() {
    if (this.window && !this.window.isDestroyed()) this.window.webContents.stop();
  }
}

module.exports = { BidCarsBrowser, HOME, isBidCars };
