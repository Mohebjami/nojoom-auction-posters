const { test } = require('node:test');
const assert = require('node:assert/strict');
const { photoView, photoDescription, selectPosterPhotos } = require('../photo-finder/photo-views.cjs');

test('identifies explicit viewpoints and rejects details and numbered galleries', () => {
  for (const [label, expected] of [['Front left', 'front'], ['rear right', 'rear'], ['back view', 'rear'], ['driver side', 'side'], ['front seats', 'interior'], ['rear cabin', 'interior'], ['Dashboard', 'interior'], ['VIN ABC Front', 'front'], ['photo no. 1', null], ['front bumper closeup', null], ['rear wheel', null], ['engine', null], ['front and back', null]]) {
    assert.equal(photoView(label), expected, label);
  }
  assert.equal(photoView(photoDescription('https://images.bid.cars/123/front_left.jpg')), 'front');
  assert.equal(photoView(photoDescription('https://images.bid.cars/side/001.jpg')), null);
});

test('orders all four slots without moving later views into missing slots', async () => {
  const items = [
    { url: 'https://images.bid.cars/4.jpg', description: 'Rear', sha256: 'rear' },
    { url: 'https://images.bid.cars/2.jpg', description: 'Side', sha256: 'side' },
    { url: 'https://images.bid.cars/1.jpg', description: 'Front', sha256: 'front' },
    { url: 'https://images.bid.cars/3.jpg', description: 'Photo no. 9', sha256: 'unknown' },
  ];
  const result = await selectPosterPhotos({ manifest: { photos: items } }, async item => item.sha256);
  assert.deepEqual(result.photos, ['front', null, 'side', 'rear']);
  assert.deepEqual(result.missingViews, ['interior']);
});

test('ignores corrupt files and never reuses the same image for different views', async () => {
  const items = [
    { description: 'Front', sha256: 'corrupt' },
    { description: 'Front', sha256: 'same' },
    { description: 'Side', sha256: 'same' },
    { description: 'Side', sha256: 'other' },
  ];
  const result = await selectPosterPhotos({ manifest: { photos: items } }, async item => item.sha256 === 'corrupt' ? null : item.sha256);
  assert.deepEqual(result.photos, ['same', null, 'other', null]);
});
