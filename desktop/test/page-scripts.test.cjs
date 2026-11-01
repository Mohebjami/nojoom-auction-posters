const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const { parseHTML } = require('linkedom');
const { inspectPage, callScript } = require('../photo-finder/page-scripts.cjs');
const VIN = 'JTDKN3DU5B0249292';
const OTHER = 'JTEZU17R868042363';
function page(html, pathname = `/en/lot/1-73097295/2011-Toyota-Prius-${VIN}`) {
  const { window } = parseHTML(`<html><head><title>Bid.Cars</title></head><body>${html}</body></html>`);
  const timers = [];
  const context = vm.createContext({ document: window.document, location: { pathname, href: `https://bid.cars${pathname}` }, URL,
    HTMLInputElement: window.HTMLInputElement, Event: window.Event, setTimeout: fn => timers.push(fn) });
  window.HTMLElement.prototype.getClientRects = () => [{}];
  return { run: (fn, ...args) => JSON.parse(JSON.stringify(vm.runInContext(callScript(fn, ...args), context))), document: window.document, timers };
}
test('downloads primary VIN gallery only; excludes thumbnails, related vehicles, and logos', () => {
  const p = page(`<h1>${VIN}</h1>
    <a href="https://images.bid.cars/1-73097295/full-1.jpg"><img alt="${VIN} 2011 Toyota Prius photo no. 1" src="https://images.bid.cars/thumb-1.jpg"></a>
    <img alt="${VIN} 2011 Toyota Prius Thumbnail photo no. 1" src="https://images.bid.cars/thumb-1.jpg">
    <img alt="${OTHER} 2006 Toyota photo no. 1" src="https://images.bid.cars/unrelated.jpg">
    <img alt="Logo" src="https://images.bid.cars/logo.jpg">
    <img alt="${VIN} photo no. 2" data-src="https://images.bid.cars/full-2.jpg" src="/placeholder.svg">
    <img alt="${VIN} photo no. 2" src="https://images.bid.cars/full-2.jpg">
    <img alt="${VIN} photo no. 3" src="https://evil.example/car.jpg">`);
  const result = p.run(inspectPage, VIN);
  assert.equal(result.verified, true);
  assert.deepEqual(result.images, ['https://images.bid.cars/1-73097295/full-1.jpg', 'https://images.bid.cars/full-2.jpg']);
});
test('no photos are accepted when the primary VIN heading mismatches', () => {
  const result = page(`<h1>${OTHER}</h1><img alt="${VIN} photo no. 1" src="https://images.bid.cars/photo.jpg">`).run(inspectPage, VIN);
  assert.equal(result.verified, false);
  assert.equal(result.images.length, 0);
});
test('search results must end in the exact VIN and use the real site host', () => {
  const p = page(`<h1>Search results</h1><a href="/en/lot/1-123/Toyota-${VIN}">Exact</a><a href="/en/lot/1-123/Toyota-${VIN}">Duplicate</a>
    <a href="https://evil.example/en/lot/1/Toyota-${VIN}">Wrong host</a><a href="/en/lot/1-123/Toyota-${VIN}X">Partial</a>
    <a href="/en/lot/1-123/Toyota-${OTHER}">Other</a>`, '/en/search/results');
  const result = p.run(inspectPage, VIN);
  assert.equal(result.links.length, 1);
  assert.equal(result.verified, false);
});
test('detects verification and explicit empty results', () => {
  const p = page('<h1>Verify you are human</h1>');
  assert.equal(p.run(inspectPage, VIN).blocked, true);
  assert.equal(page('<h1>No vehicles found</h1>', '/en/search/results').run(inspectPage, VIN).noResults, true);
});
test('chooses the largest responsive image', () => {
  const p = page(`<h1>${VIN}</h1><img alt="${VIN} photo no. 1" src="https://images.bid.cars/small.jpg" srcset="https://images.bid.cars/medium.jpg 600w, https://images.bid.cars/large.jpg 1600w">`);
  assert.deepEqual(p.run(inspectPage, VIN).images, ['https://images.bid.cars/large.jpg']);
});
test('current Bid.Cars gallery uses a full-size Pluto URL on the parent slide', () => {
  const p = page(`<h1>${VIN}</h1>
    <div class="f-carousel__slide" data-fancybox="gallery" data-src="https://pluto.bid.car/1-73097295/Prius-${VIN}-1.jpg">
      <img src="https://mercury.bid.cars/1-73097295/Prius-${VIN}-1.jpg" alt="${VIN} 2011 Toyota Prius photo no. 1">
    </div>
    <img src="https://mercury.bid.cars/1-73097295/Prius-${VIN}-1.jpg" alt="${VIN} Thumbnail photo no. 1">`);
  assert.deepEqual(p.run(inspectPage, VIN).images, [`https://pluto.bid.car/1-73097295/Prius-${VIN}-1.jpg`]);
});
