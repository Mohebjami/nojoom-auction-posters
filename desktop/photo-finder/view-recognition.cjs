const path = require('node:path');

const MODEL = 'Xenova/clip-vit-base-patch32';
const VERSION = 'clip-car-views-v1';
// Include non-poster images so a detail shot is not forced into a vehicle view.
const CANDIDATES = [
  ['front', 'the exterior front of a car, showing its headlights and front grille'],
  ['rear', 'the exterior rear of a car, showing its tail lights and rear bumper'],
  ['side', 'the exterior side profile of a car, showing its side doors and wheels'],
  ['interior', 'the inside cabin of a car, showing seats, steering wheel and dashboard'],
  [null, 'a close-up of a car engine under the hood'],
  [null, 'a close-up of a vehicle identification number or a document'],
  [null, 'a close-up of an odometer or instrument cluster'],
  [null, 'a close-up of a wheel, tire or damaged car part'],
  [null, 'a car trunk or cargo compartment'],
  [null, 'an unrelated image, a logo, or no visible car'],
];

function decideView(predictions) {
  const ranked = [...predictions].sort((a, b) => b.score - a.score);
  const best = ranked[0];
  const view = CANDIDATES.find(([, label]) => label === best?.label)?.[0] || null;
  const score = Number(best?.score) || 0;
  const margin = score - (Number(ranked[1]?.score) || 0);
  // CLIP scores are a ranking, not a guarantee. Ambiguous views need review.
  return { version: VERSION, view: view && score >= 0.6 && margin >= 0.15 ? view : null, score, margin };
}

function acceptedModelView(result) {
  return result?.version === VERSION && ['front', 'interior', 'side', 'rear'].includes(result.view) &&
    result.score >= 0.6 && result.margin >= 0.15 ? result.view : null;
}

function abortable(promise, signal, timeoutMs = 120000) {
  return new Promise((resolve, reject) => {
    let timer;
    const finish = (error, value) => {
      clearTimeout(timer);
      signal?.removeEventListener('abort', onAbort);
      if (error) reject(error);
      else resolve(value);
    };
    const onAbort = () => finish(signal.reason || new Error('Stopped'));
    timer = setTimeout(() => finish(new Error('Photo recognition took too long. Unidentified views need manual selection.')), timeoutMs);
    signal?.addEventListener('abort', onAbort, { once: true });
    Promise.resolve(promise).then(value => finish(null, value), error => finish(error));
    if (signal?.aborted) onAbort();
  });
}

async function loadRecognitionModel({ cacheDir, onProgress }) {
  const { pipeline, RawImage } = await import('@huggingface/transformers');
  const classifier = await pipeline('zero-shot-image-classification', MODEL, {
    dtype: 'q8', device: 'cpu', cache_dir: cacheDir, progress_callback: onProgress,
  });
  return { classifier, RawImage };
}

function createViewRecognizer({ runtimePath, onMessage = () => {}, loadModel = loadRecognitionModel }) {
  let loading;
  let unavailable = false;
  let warning = '';
  async function load() {
    if (!loading) {
      onMessage('Preparing local photo recognition. The first run downloads an AI model; vehicle photos stay on this computer.');
      loading = (async () => {
        const model = await loadModel({
          cacheDir: path.join(runtimePath, 'photo-view-model'),
          onProgress: update => {
            if (update.status === 'progress' && Number.isFinite(update.progress)) {
              onMessage(`First-time photo recognition setup · ${Math.round(update.progress)}% of the current model file downloaded. Stop is available.`);
            }
          },
        });
        onMessage('Local photo recognition ready. Identifying vehicle views…');
        return model;
      })().catch(error => { loading = null; throw error; });
    }
    return loading;
  }
  return {
    async classify(file, signal) {
      if (unavailable) return null;
      let model;
      try {
        model = await abortable(load(), signal, 30 * 60 * 1000);
      } catch (error) {
        signal?.throwIfAborted();
        // One model/network failure must not prevent downloading the gallery.
        unavailable = true;
        warning = 'Automatic angle recognition is unavailable. Select the flagged views manually, or retry the download later.';
        onMessage(`Photo recognition unavailable: ${error.message}. Unidentified views will be flagged for manual selection.`);
        return null;
      }
      signal?.throwIfAborted();
      try {
        const image = await abortable(model.RawImage.read(file), signal);
        const predictions = await abortable(model.classifier(image, CANDIDATES.map(([, label]) => label)), signal);
        signal?.throwIfAborted();
        return decideView(predictions);
      } catch (error) {
        signal?.throwIfAborted();
        onMessage(`A photo could not be identified: ${error.message}. Its view needs manual selection.`);
        return { version: VERSION, view: null, score: 0, margin: 0 };
      }
    },
    get warning() { return warning; },
    retry() { unavailable = false; warning = ''; },
  };
}

module.exports = { MODEL, VERSION, CANDIDATES, decideView, acceptedModelView, createViewRecognizer, abortable };
