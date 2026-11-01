const fs = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');

const MAX_BYTES = 35 * 1024 * 1024;
const PHOTO_HOSTS = new Set(['images.bid.cars', 'mercury.bid.cars', 'pluto.bid.car', 'bid.cars', 'www.bid.cars']);
function isBidCarsPhotoURL(value) {
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && PHOTO_HOSTS.has(url.hostname) && !url.username && !url.password && (!url.port || url.port === '443');
  } catch { return false; }
}
function isNCAPhotoURL(value) {
  try {
    const url = new URL(value);
    return url.origin === 'https://nap.fsn1.your-objectstorage.com' && !url.username && !url.password &&
      /^\/noewarid\/file-manager\/vehicles\/\d+\/[^/]+\.(jpe?g|png|webp|gif|avif)$/i.test(url.pathname);
  } catch { return false; }
}
const isPhotoURL = value => isBidCarsPhotoURL(value) || isNCAPhotoURL(value);
function imageExtension(bytes) {
  if (bytes.length < 12) return null;
  if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return 'jpg';
  if (bytes.subarray(0, 8).equals(Buffer.from([137,80,78,71,13,10,26,10]))) return 'png';
  if (bytes.toString('ascii', 0, 4) === 'RIFF' && bytes.toString('ascii', 8, 12) === 'WEBP') return 'webp';
  if (/^GIF8[79]a$/.test(bytes.toString('ascii', 0, 6))) return 'gif';
  if (bytes.toString('ascii', 4, 8) === 'ftyp' && /avif|avis/.test(bytes.toString('ascii', 8, 32))) return 'avif';
  return null;
}
const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');

async function verifiedFile(directory, item) {
  if (!item || !/^\d{3}-[a-f0-9]{12}\.(jpg|png|webp|gif|avif)$/.test(item.file) || !/^[a-f0-9]{64}$/.test(item.sha256)) return false;
  try {
    const file = path.join(directory, item.file);
    const stat = await fs.lstat(file);
    if (!stat.isFile() || stat.isSymbolicLink() || stat.size > MAX_BYTES) return false;
    const bytes = await fs.readFile(file);
    return !!imageExtension(bytes) && digest(bytes) === item.sha256;
  } catch { return false; }
}

async function openDestination(base, vehicle) {
  if (!/^[0-9]+\. [A-HJ-NPR-Z0-9]{17}$/.test(vehicle.folder)) throw new Error('Invalid vehicle folder name.');
  const realBase = await fs.realpath(base);
  const directory = path.join(realBase, vehicle.folder);
  await fs.mkdir(directory, { recursive: true });
  const stat = await fs.lstat(directory);
  if (!stat.isDirectory() || stat.isSymbolicLink()) throw new Error('The vehicle destination must be a regular folder.');
  const manifestFile = path.join(directory, 'photos.json');
  let manifest;
  try {
    const stat = await fs.lstat(manifestFile);
    if (stat.isSymbolicLink() || stat.size > 2 * 1024 * 1024) throw new Error('Unsafe photo manifest.');
    manifest = JSON.parse(await fs.readFile(manifestFile, 'utf8'));
    if (manifest.vin !== vehicle.vin || !Array.isArray(manifest.photos)) throw new Error('Photo manifest does not match this VIN.');
  } catch (error) {
    if (error.code !== 'ENOENT') throw new Error(`Cannot resume this folder: ${error.message}`);
    manifest = { version: 1, vin: vehicle.vin, no: vehicle.no, photos: [] };
  }
  return { directory, manifestFile, manifest };
}

async function saveManifest(destination) {
  const temporary = `${destination.manifestFile}.${crypto.randomUUID()}.tmp`;
  try {
    await fs.writeFile(temporary, JSON.stringify(destination.manifest, null, 2), { flag: 'wx' });
    await fs.rename(temporary, destination.manifestFile);
  } finally { await fs.rm(temporary, { force: true }); }
}

async function downloadPhoto({ destination, url, index, fetchPhoto, signal }) {
  if (!isPhotoURL(url)) throw new Error('Photo URL is outside the supported image hosts.');
  const previous = destination.manifest.photos.find(p => p.url === url);
  if (await verifiedFile(destination.directory, previous)) return { ...previous, resumed: true };
  signal?.throwIfAborted();
  const response = await fetchPhoto(url, signal);
  if (!response.ok) throw new Error(`Photo server returned HTTP ${response.status}.`);
  if (response.url && !isPhotoURL(response.url)) throw new Error('Photo redirected outside the supported image hosts.');
  const length = Number(response.headers.get('content-length'));
  if (length > MAX_BYTES) throw new Error('Photo exceeds the 35 MB size limit.');
  const chunks = [];
  let size = 0;
  try {
    for await (const chunk of response.body) {
      signal?.throwIfAborted();
      size += chunk.length;
      if (size > MAX_BYTES) throw new Error('Photo exceeds the 35 MB size limit.');
      chunks.push(Buffer.from(chunk));
    }
  } catch (error) { await response.body?.cancel?.().catch(() => {}); throw error; }
  const bytes = Buffer.concat(chunks);
  const extension = imageExtension(bytes);
  if (!extension) throw new Error('The server returned a page or unsupported file instead of a photo.');
  const sha256 = digest(bytes);
  const duplicate = destination.manifest.photos.find(p => p.sha256 === sha256);
  if (await verifiedFile(destination.directory, duplicate)) {
    const item = { ...duplicate, url };
    destination.manifest.photos = destination.manifest.photos.filter(p => p.url !== url).concat(item);
    await saveManifest(destination);
    return { ...item, duplicate: true };
  }
  const temporary = path.join(destination.directory, `.photo-${crypto.randomUUID()}.tmp`);
  let item;
  try {
    await fs.writeFile(temporary, bytes, { flag: 'wx' });
    for (let number = index + 1; number <= 999; number++) {
      const file = `${String(number).padStart(3, '0')}-${sha256.slice(0, 12)}.${extension}`;
      item = { url, file, sha256, bytes: bytes.length };
      const target = path.join(destination.directory, file);
      try {
        // A completed temporary file is linked atomically without overwriting anything.
        try { await fs.link(temporary, target); }
        catch (error) {
          if (!['EPERM', 'EOPNOTSUPP', 'ENOTSUP'].includes(error.code)) throw error;
          await fs.copyFile(temporary, target, require('node:fs').constants.COPYFILE_EXCL);
        }
        break;
      } catch (error) {
        if (error.code !== 'EEXIST') throw error;
        if (await verifiedFile(destination.directory, item)) break;
        // Preserve an interrupted/corrupt file and recover into the next free name.
        item = null;
      }
    }
  } finally { await fs.rm(temporary, { force: true }); }
  if (!item) throw new Error('No free photo filename remains in this folder.');
  destination.manifest.photos = destination.manifest.photos.filter(p => p.url !== url).concat(item);
  await saveManifest(destination);
  return item;
}

module.exports = { isPhotoURL, isBidCarsPhotoURL, isNCAPhotoURL, imageExtension, verifiedFile, openDestination, saveManifest, downloadPhoto };
