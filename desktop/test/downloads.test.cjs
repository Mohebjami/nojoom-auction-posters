const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const { isPhotoURL, imageExtension, openDestination, downloadPhoto, verifiedFile } = require('../photo-finder/downloads.cjs');
const VIN = 'JTDKN3DU5B0249292';
const vehicle = { vin: VIN, no: '1', folder: `1. ${VIN}` };
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aN1cAAAAASUVORK5CYII=', 'base64');
async function destination(t) {
  const base = await fs.mkdtemp(path.join(os.tmpdir(), 'auction-photo-test-'));
  t.after(() => fs.rm(base, { recursive: true, force: true }));
  return { base, ...await openDestination(base, vehicle) };
}
test('restricts photo requests to HTTPS Bid.Cars hosts', () => {
  assert.equal(isPhotoURL('https://images.bid.cars/photo.jpg'), true);
  assert.equal(isPhotoURL('https://pluto.bid.car/photo.jpg'), true);
  assert.equal(isPhotoURL('https://mercury.bid.cars/photo.jpg'), true);
  for (const url of ['file:///etc/passwd', 'http://images.bid.cars/a', 'https://images.bid.cars.evil.example/a', 'https://user@images.bid.cars/a', 'https://images.bid.cars:9999/a']) assert.equal(isPhotoURL(url), false);
});
test('rejects HTML verification pages as images', async t => {
  const dest = await destination(t);
  assert.equal(imageExtension(Buffer.from('<html>not a photo</html>')), null);
  await assert.rejects(downloadPhoto({ destination: dest, url: 'https://images.bid.cars/a.jpg', index: 0, fetchPhoto: async () => new Response('<html>verify</html>') }), /instead of a photo/);
  assert.deepEqual(await fs.readdir(dest.directory), []);
});
test('saves into numbered VIN folder, resumes without fetching, and deduplicates bytes', async t => {
  const dest = await destination(t);
  let calls = 0;
  const fetchPhoto = async () => { calls++; return new Response(png); };
  const options = { destination: dest, url: 'https://images.bid.cars/photo.png', index: 0, fetchPhoto };
  const first = await downloadPhoto(options);
  assert.equal(path.basename(dest.directory), vehicle.folder);
  assert.ok(await verifiedFile(dest.directory, first));
  assert.equal((await downloadPhoto(options)).resumed, true);
  assert.equal(calls, 1);
  const duplicate = await downloadPhoto({ ...options, index: 1, url: 'https://images.bid.cars/duplicate.png' });
  assert.equal(duplicate.duplicate, true);
  assert.equal(duplicate.file, first.file);
  const reopened = await openDestination(dest.base, vehicle);
  assert.equal((await downloadPhoto({ ...options, destination: reopened })).resumed, true);
  assert.equal((await fs.readdir(dest.directory)).length, 2); // One photo + photos.json.
});
test('recovers a corrupt photo while preserving the old file', async t => {
  const dest = await destination(t);
  const options = { destination: dest, url: 'https://images.bid.cars/photo.png', index: 0, fetchPhoto: async () => new Response(png) };
  const first = await downloadPhoto(options);
  await fs.writeFile(path.join(dest.directory, first.file), 'corrupt');
  const repaired = await downloadPhoto(options);
  assert.notEqual(first.file, repaired.file);
  assert.ok(await verifiedFile(dest.directory, repaired));
  assert.equal(await fs.readFile(path.join(dest.directory, first.file), 'utf8'), 'corrupt');
});
test('rejects folder traversal and vehicle-folder symlinks', async t => {
  const dest = await destination(t);
  await assert.rejects(openDestination(dest.base, { ...vehicle, folder: '../escape' }), /Invalid/);
  const second = { ...vehicle, no: '2', folder: `2. ${VIN}` };
  await fs.symlink(dest.directory, path.join(dest.base, second.folder), 'dir');
  await assert.rejects(openDestination(dest.base, second), /regular folder/);
});
test('checks declared size and respects cancellation', async t => {
  const dest = await destination(t);
  await assert.rejects(downloadPhoto({ destination: dest, url: 'https://images.bid.cars/huge.jpg', index: 0, fetchPhoto: async () => new Response(png, { headers: { 'content-length': String(40 * 1024 * 1024) } }) }), /size limit/);
  const controller = new AbortController(); controller.abort();
  await assert.rejects(downloadPhoto({ destination: dest, url: 'https://images.bid.cars/cancel.jpg', index: 0, signal: controller.signal, fetchPhoto: async () => { throw new Error('Must not fetch'); } }), /abort/i);
});
