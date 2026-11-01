const { VIN_PATTERN, normalizeVIN } = require('./workbook.cjs');
const { isBidCarsPhotoURL: isPhotoURL } = require('./downloads.cjs');

// These are the public URLs used by Bid.Cars' own search JavaScript.
function searchURL(vin, archived, api = false) {
  if (!VIN_PATTERN.test(vin)) throw new Error('A complete VIN is required for search.');
  const url = new URL(`https://bid.cars/${api ? 'app' : 'en'}/search/${archived ? 'archived/' : ''}${api ? 'request' : 'results'}`);
  url.searchParams.set('search-type', 'typing');
  url.searchParams.set('query', vin);
  url.searchParams.set('status', 'All');
  return url.href;
}

function parseSearch(payload, vin, archived) {
  if (!payload || !Array.isArray(payload.data)) throw new Error('Bid.Cars returned an unexpected search response.');
  const exact = payload.data.filter(record => normalizeVIN(record.vin) === vin);
  for (const record of exact) {
    const lot = String(record.lot || '');
    const tag = String(record.tag || '');
    if (!/^\d+-\d+$/.test(lot) || tag.includes('/') || !tag.toUpperCase().endsWith(`-${vin}`)) continue;
    const source = new URL(`https://bid.cars/en/lot/${lot}/${encodeURIComponent(tag)}`);
    if (archived) source.searchParams.set('archived', 'true');
    const images = [...new Set(Object.values(record.img_large || {}).filter(value => typeof value === 'string' && isPhotoURL(value)))].slice(0, 200);
    return { source: source.href, images };
  }
  if (exact.length) throw new Error('Bid.Cars returned the VIN without a valid vehicle listing URL.');
  return null;
}

module.exports = { searchURL, parseSearch };
