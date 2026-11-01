const { test } = require('node:test');
const assert = require('node:assert/strict');
const { CANDIDATES, VERSION, decideView, acceptedModelView, abortable, createViewRecognizer } = require('../photo-finder/view-recognition.cjs');

test('confident visual predictions map to the four semantic views', () => {
  for (const [view, label] of CANDIDATES.filter(([view]) => view)) {
    const result = decideView([{ label, score: .85 }, { label: 'other', score: .1 }]);
    assert.equal(result.view, view);
    assert.equal(acceptedModelView(result), view);
  }
});

test('ambiguous angles, detail shots and unknown results stay blank', () => {
  const front = CANDIDATES.find(([view]) => view === 'front')[1];
  const rear = CANDIDATES.find(([view]) => view === 'rear')[1];
  const detail = CANDIDATES.find(([view]) => view === null)[1];
  assert.equal(decideView([{ label: front, score: .48 }, { label: rear, score: .4 }]).view, null);
  assert.equal(decideView([{ label: front, score: .64 }, { label: rear, score: .6 }]).view, null);
  assert.equal(decideView([{ label: detail, score: .95 }]).view, null);
  assert.equal(decideView([]).view, null);
  assert.equal(acceptedModelView({version: VERSION, view: 'rear', score: .4, margin: .3}), null);
  assert.equal(acceptedModelView({version: 'old', view: 'rear', score: .9, margin: .8}), null);
});

test('Stop interrupts a model download or inference and timeouts do not hold the batch open', async () => {
  const controller = new AbortController();
  const waiting = abortable(new Promise(() => {}), controller.signal);
  controller.abort();
  await assert.rejects(waiting, /abort/i);
  await assert.rejects(abortable(new Promise(() => {}), undefined, 5), /too long/);
  assert.equal(await abortable(Promise.resolve('ready')), 'ready');
});

test('model setup is reused and an unavailable model retries on the next batch', async () => {
  let setups = 0;
  const front = CANDIDATES.find(([view]) => view === 'front')[1];
  const recognizer = createViewRecognizer({runtimePath: '/tmp/models', loadModel: async () => {
    if (++setups === 1) throw new Error('Network unavailable');
    return {RawImage: {read: async file => file}, classifier: async () => [{label: front, score: .95}]};
  }});
  assert.equal(await recognizer.classify('/tmp/car.jpg'), null);
  assert.match(recognizer.warning, /unavailable/);
  assert.equal(await recognizer.classify('/tmp/another.jpg'), null);
  assert.equal(setups, 1);
  recognizer.retry();
  assert.equal((await recognizer.classify('/tmp/car.jpg')).view, 'front');
  assert.equal((await recognizer.classify('/tmp/another.jpg')).view, 'front');
  assert.equal(setups, 2);
  assert.equal(recognizer.warning, '');
});

test('one undecodable photo does not disable recognition of the rest of the gallery', async () => {
  const side = CANDIDATES.find(([view]) => view === 'side')[1];
  const recognizer = createViewRecognizer({runtimePath: '/tmp/models', loadModel: async () => ({
    RawImage: {read: async file => { if (file === 'bad') throw new Error('Invalid photo'); return file; }},
    classifier: async () => [{label: side, score: .95}],
  })});
  assert.equal((await recognizer.classify('bad')).view, null);
  assert.equal((await recognizer.classify('good')).view, 'side');
});
