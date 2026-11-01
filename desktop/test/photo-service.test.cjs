const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { createPhotoService } = require('../photo-service.cjs');
const { VERSION } = require('../photo-finder/view-recognition.cjs');
const VIN = 'JTDKN3DU0B1457686';
const OTHER = 'JTDKN3DU2A0090987';
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aN1cAAAAASUVORK5CYII=', 'base64');
async function service(t, {recognizer, images = ['https://images.bid.cars/rear.jpg']} = {}) {
  const runtimePath = await fs.mkdtemp(path.join(os.tmpdir(), 'single-photo-search-'));
  t.after(() => fs.rm(runtimePath, { recursive: true, force: true }));
  const calls = [];
  const source = { lookup: async vin => { calls.push(vin); return { source: 'https://bid.cars/en/lot/1-123/car-' + vin, images }; }, fetchPhoto: async url => new Response(images.length === 1 ? png : Buffer.concat([png, Buffer.from(url)])), stopNavigation() {} };
  const result = createPhotoService({runtimePath, recognizer, browsers: { bidcars: source, nca: source }});
  await result.initialize();
  await result.command('set-output', { directory: runtimePath });
  return { result, calls };
}
async function finish(result) {
  for (let i = 0; i < 150 && result.state.running; i++) await new Promise(resolve => setTimeout(resolve, 20));
  assert.equal(result.state.running, false);
}
test('single VIN search preserves the imported list and processes only the chosen vehicle', async t => {
  const { result, calls } = await service(t);
  const existing = { id: 'imported', no: '8', vin: OTHER, status: 'ready', count: 0, folder: `8. ${OTHER}` };
  result.state.vehicles.push(existing);
  await result.command('search-one', { vin: VIN.toLowerCase(), no: '25' });
  await finish(result);
  assert.deepEqual(calls, [VIN]);
  assert.equal(existing.status, 'ready');
  assert.equal(result.state.vehicles.length, 2);
  const row = result.state.vehicles[1];
  assert.equal(row.status, 'done');
  assert.equal(row.no, '25');
  const photos = await result.posterPhotos(row.id);
  assert.deepEqual(photos.missingViews, ['front', 'interior', 'side']);
  assert.deepEqual(photos.photos.slice(0, 3), [null, null, null]);
  assert.equal(photos.photos[3], png.toString('base64'));
  assert.equal(photos.vin, VIN);
  await result.command('search-one', { vin: VIN });
  await finish(result);
  assert.equal(result.state.vehicles.length, 2);
  assert.deepEqual(calls, [VIN, VIN]);
});
test('invalid VIN, invalid No. and missing destination never alter the list or search', async t => {
  const { result, calls } = await service(t);
  await assert.rejects(result.command('search-one', { vin: 'invalid' }), /17-character/);
  await assert.rejects(result.command('search-one', { vin: VIN, no: '../1' }), /positive whole/);
  result.state.output = '/a-folder-that-does-not-exist';
  await assert.rejects(result.command('search-one', { vin: VIN }), /destination/);
  assert.deepEqual(calls, []);
  assert.deepEqual(result.state.vehicles, []);
});

test('unlabelled galleries use local visual recognition, persist results, and leave uncertain views blank', async t => {
  const calls = [];
  const recognizer = { classify: async file => {
    calls.push(file);
    const view = path.basename(file).startsWith('001-') ? 'rear' : path.basename(file).startsWith('002-') ? 'front' : null;
    return { version: VERSION, view, score: view ? .9 : .3, margin: view ? .8 : .05 };
  } };
  const { result } = await service(t, {recognizer, images: [1, 2, 3].map(i => `https://images.bid.cars/${i}.jpg`)});
  await result.command('search-one', { vin: VIN });
  await finish(result);
  const row = result.state.vehicles[0];
  assert.equal(row.status, 'done');
  assert.equal(calls.length, 3);
  let photos = await result.posterPhotos(row.id);
  assert.ok(photos.photos[0]);
  assert.equal(photos.photos[1], null);
  assert.equal(photos.photos[2], null);
  assert.ok(photos.photos[3]);
  assert.deepEqual(photos.missingViews, ['interior', 'side']);
  await result.command('start', { mode: 'single', id: row.id });
  await finish(result);
  assert.equal(calls.length, 3); // Reuses the saved recognition for each hash.
  assert.deepEqual((await result.posterPhotos(row.id)).photos, photos.photos);
});

test('Stop remains usable while identifying downloaded images', async t => {
  let began;
  const started = new Promise(resolve => { began = resolve; });
  const recognizer = { classify: async (_file, signal) => {
    began();
    return new Promise((_, reject) => signal.addEventListener('abort', () => reject(signal.reason), {once: true}));
  } };
  const { result } = await service(t, {recognizer, images: ['https://images.bid.cars/1.jpg']});
  await result.command('search-one', {vin: VIN});
  await started;
  assert.equal(result.state.vehicles[0].status, 'classifying');
  await result.command('stop');
  await finish(result);
  assert.equal(result.state.vehicles[0].status, 'stopped');
  assert.equal(result.state.vehicles[0].count, 1);
});
