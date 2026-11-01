const { acceptedModelView } = require('./view-recognition.cjs');
// Gallery order varies by auction. Use explicit descriptions or a confident
// local model result, keeping unidentified images available for manual use.
const VIEWS = ['front', 'interior', 'side', 'rear'];

function photoView(description) {
  const text = String(description || '').toLowerCase().replace(/[_-]+/g, ' ');
  // These detail shots are not a usable exterior or cabin view.
  if (/\b(engine|odometer|wheel|tire|tyre|damage|trunk|boot|underbody|undercarriage|airbag|mirror|bumper|headlight|taillight)\b/.test(text) || /\bvin\s+(plate|number|sticker|label|close up)\b/.test(text)) return null;
  if (/\b(interior|inside|cabin|dashboard|cockpit|seats?)\b/.test(text)) return 'interior';
  const front = /\bfront\b/.test(text);
  const rear = /\b(rear|back)\b/.test(text);
  if (front && rear) return null;
  if (front) return 'front';
  if (rear) return 'rear';
  if (/\b(side|profile|left|right|driver side|passenger side)\b/.test(text)) return 'side';
  return null;
}

function photoDescription(url, label = '') {
  // Ignore the VIN/model in URL paths; use only descriptive filename words.
  let filename = '';
  try { filename = decodeURIComponent(new URL(url).pathname.split('/').pop()); } catch {}
  return [label, filename.replace(/\.(jpe?g|png|webp|gif|avif)$/i, '')].filter(Boolean).join(' ');
}

async function selectPosterPhotos(destination, readPhoto) {
  const photos = Array(4).fill(null);
  const seen = new Set();
  for (const item of destination.manifest.photos) {
    const view = photoView(photoDescription(item.url, item.description)) || acceptedModelView(item.classification);
    const slot = VIEWS.indexOf(view);
    if (slot < 0 || photos[slot] !== null || seen.has(item.sha256)) continue;
    const bytes = await readPhoto(item);
    if (!bytes) continue;
    photos[slot] = bytes;
    seen.add(item.sha256);
  }
  return { photos, views: VIEWS, missingViews: VIEWS.filter((_, i) => photos[i] === null) };
}

module.exports = { VIEWS, photoView, photoDescription, selectPosterPhotos };
