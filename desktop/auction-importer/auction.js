export const LOCATION = 'Herat NCA Branch';
export const SELL_TYPE = 'On Approval';
const clean = text => text.replace(/\s+/g, ' ').trim();
const money = text => Number(text.replace(/[$,\s]/g, ''));

export function checkListing(actual, vehicle, item) {
  const failures = [];
  if (item !== undefined && actual.item !== item) failures.push(`item ${actual.item}, expected ${item}`);
  if (!actual.start.trim() || money(actual.start) !== vehicle.biddingStart) failures.push(`starting bid ${actual.start}, expected ${vehicle.biddingStart}`);
  if (!actual.reserve.trim() || money(actual.reserve) !== vehicle.greenLight) failures.push(`green light ${actual.reserve}, expected ${vehicle.greenLight}`);
  if (actual.sellType !== SELL_TYPE) failures.push(`sell type ${actual.sellType}`);
  if (actual.location !== `Afghanistan (${LOCATION})`) failures.push(`location ${actual.location}`);
  if (failures.length) throw new Error(`Lot ${actual.lot} is in the auction with different values: ${failures.join('; ')}. Review it on the website before continuing.`);
}

export class NcaAuction {
  constructor(page, url, timeout = 30000) {
    this.page = page;
    this.url = new URL(url);
    this.timeout = timeout;
    this.dialogError = null;
    page.setDefaultTimeout(timeout);
    page.setDefaultNavigationTimeout(timeout);
    page.on('dialog', async dialog => {
      this.dialogError = `${dialog.type()}: ${dialog.message()}`;
      await dialog.dismiss();
    });
    this.searchTable = page.locator('table').filter({has: page.locator('thead').filter({hasText: 'Assign Auction'})});
    this.listTable = page.locator('table').filter({has: page.locator('thead').filter({hasText: 'Starting Bid'})});
    this.modal = page.locator('#modal-push-to-auction');
  }

  async login(email, password) {
    await this.page.goto(new URL('/login', this.url).href);
    await this.page.getByPlaceholder('you@example.com').fill(email);
    await this.page.getByPlaceholder('Enter your password').fill(password);
    await this.page.getByRole('button', {name: /sign in/i}).click();
    try {
      await this.page.waitForURL(url => !url.pathname.startsWith('/login'), {timeout: this.timeout});
    } catch {
      throw new Error('Sign-in did not complete. Check NCA_EMAIL and NCA_PASSWORD, and whether the site requires a manual login step.');
    }
    await this.open();
  }

  async open(vin) {
    const url = new URL(this.url);
    url.search = '';
    if (vin) url.searchParams.set('auctionSearch', vin);
    await this.page.goto(url.href);
    if (new URL(this.page.url()).pathname.startsWith('/login')) throw new Error('Your session expired. Restart the importer to sign in again.');
    await this.listTable.waitFor({state: 'visible'});
  }

  async listings() {
    const rows = await this.listTable.locator('tbody tr').evaluateAll(elements => elements.map(row =>
      [...row.cells].map(cell => cell.textContent.replace(/\s+/g, ' ').trim())
    ));
    const results = rows.filter(cells => cells.length >= 10).map(cells => ({
      item: Number(cells[0]), lot: cells[1], reserve: cells[4], start: cells[5], sellType: cells[6], location: cells[7],
    }));
    if (results.some(row => !Number.isSafeInteger(row.item) || row.item < 1 || !/^\d+$/.test(row.lot))) {
      throw new Error('Unexpected auction list format. Review the page before importing.');
    }
    if (new Set(results.map(row => row.item)).size !== results.length || new Set(results.map(row => row.lot)).size !== results.length) {
      throw new Error('The auction already contains duplicate item numbers or lots. Review the auction list first.');
    }
    return results;
  }

  async findVehicle(vin) {
    await this.open(vin);
    const candidates = this.searchTable.locator('tbody tr').filter({has: this.page.locator('[aria-label="Add to Auction"]')});
    const count = await candidates.count();
    if (!count) throw new Error(`VIN ${vin} was not found in available vehicles.`);
    const matches = [];
    for (let index = 0; index < count; index++) {
      const row = candidates.nth(index);
      const href = await row.locator('a[href*="/inventory/view/vehicle/"]').first().getAttribute('href');
      const detailUrl = new URL(href, this.url);
      if (detailUrl.origin !== this.url.origin || !detailUrl.pathname.startsWith('/inventory/view/vehicle/')) {
        throw new Error('Vehicle details link points to an unexpected destination.');
      }
      const detail = await this.page.context().newPage();
      try {
        await detail.goto(detailUrl.href, {timeout: this.timeout});
        const vins = await detail.locator('tr').evaluateAll(rows => rows.filter(row =>
          row.cells[0]?.textContent.trim() === 'VIN'
        ).map(row => row.cells[1]?.textContent.trim().toUpperCase()));
        if (vins.length !== 1) throw new Error(`Cannot verify the full VIN on ${detailUrl.pathname}.`);
        if (vins[0] === vin) {
          const text = clean(await row.innerText());
          const lot = text.match(/Lot\s*#\s*:\s*(\d+)/i)?.[1];
          if (!lot) throw new Error(`Cannot read the lot number for VIN ${vin}.`);
          matches.push({row, lot});
        }
      } finally { await detail.close(); }
    }
    if (matches.length !== 1) throw new Error(`Expected one exact VIN match for ${vin}; found ${matches.length}.`);
    return matches[0];
  }

  async fill(vehicle, match, item) {
    this.dialogError = null;
    await match.row.locator('[aria-label="Add to Auction"]').click();
    await this.modal.waitFor({state: 'visible'});
    await this.modal.getByLabel('Item #', {exact: true}).fill(String(item));
    await this.modal.getByLabel('Sales Branch', {exact: true}).selectOption({label: 'Afghanistan'});
    await this.modal.getByLabel('Towed From (Location)', {exact: true}).fill(LOCATION);
    await this.modal.getByLabel('Shipping & Clearance Cost', {exact: true}).fill('0');
    await this.modal.getByLabel('Sell Type', {exact: true}).selectOption({label: SELL_TYPE});
    await this.modal.getByLabel('Bidding Start', {exact: true}).fill(String(vehicle.biddingStart));
    await this.modal.getByLabel('Green Light', {exact: true}).fill(String(vehicle.greenLight));
    await this.modal.getByLabel('Buy Now', {exact: true}).fill('');
    await this.modal.getByLabel('Seller Note (Optional)', {exact: true}).fill('');
    const expected = {
      modal_push_auction_item: String(item), modal_push_auction_branch_id: '3',
      modal_push_auction_towed_from: LOCATION, modal_push_auction_shipping_cost: '0',
      modal_push_auction_sell_type: SELL_TYPE, modal_push_auction_bidding_start: String(vehicle.biddingStart),
      modal_push_auction_green_price: String(vehicle.greenLight), modal_push_auction_buy_now: '',
    };
    // Validate the actual DOM values immediately before any publish click.
    for (const [id, value] of Object.entries(expected)) {
      if (await this.modal.locator(`#${id}`).inputValue() !== value) throw new Error(`The form field ${id} did not retain its expected value.`);
    }
  }

  async closeModal() {
    if (await this.modal.isVisible()) {
      // Bootstrap's outer modal is the backdrop area. This mirrors clicking outside.
      await this.modal.click({position: {x: 5, y: 5}});
      await this.modal.waitFor({state: 'hidden'});
    }
  }

  async publish() {
    const responsePromise = this.page.waitForResponse(response => {
      if (response.request().method() !== 'POST' || !new URL(response.url()).pathname.endsWith('/livewire/update')) return false;
      try {
        const data = response.request().postDataJSON();
        return data.components?.some(component => component.calls?.some(call => call.method === 'modalPushAuction'));
      } catch { return false; }
    }, {timeout: this.timeout});
    // Consume the waiter even if clicking fails, avoiding an unhandled rejection.
    const [response] = await Promise.all([
      responsePromise,
      this.modal.getByRole('button', {name: 'Yes, Publish', exact: true}).click(),
    ]);
    if (!response.ok()) throw new Error(`Publish request returned HTTP ${response.status()}.`);
    const body = await response.json();
    const returned = body.components?.flatMap(component => component.effects?.returns ?? []).find(value => value && typeof value === 'object' && 'status' in value);
    if (returned && returned.status !== 'success') throw new Error(`The website rejected publishing: ${returned.message ?? returned.status}`);
    if (this.dialogError) throw new Error(`The website reported ${this.dialogError}`);
    await this.closeModal();
  }

  async verify(vehicle, lot, item) {
    // Reload from the server: a successful click or toast alone is not verification.
    await this.open(vehicle.vin);
    const rows = (await this.listings()).filter(row => row.lot === lot);
    if (rows.length !== 1) throw new Error(`Published lot ${lot} is not present exactly once in the auction list.`);
    checkListing(rows[0], vehicle, item);
    const row = this.listTable.locator('tbody tr').filter({has: this.page.locator('td:nth-child(2)').filter({hasText: new RegExp(`^\\s*${lot}\\s*$`)})});
    await row.scrollIntoViewIfNeeded();
    return rows[0];
  }
}
