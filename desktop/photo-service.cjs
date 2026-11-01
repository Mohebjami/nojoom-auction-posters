const { dialog, shell } = require('electron');
const fs = require('node:fs/promises');
const path = require('node:path');
const { readWorkbook, normalizeVIN, VIN_PATTERN } = require('./photo-finder/workbook.cjs');
const { selectPosterPhotos, photoView, photoDescription } = require('./photo-finder/photo-views.cjs');
const { createViewRecognizer, VERSION: RECOGNITION_VERSION } = require('./photo-finder/view-recognition.cjs');
const { BidCarsBrowser, isBidCars } = require('./photo-finder/bidcars.cjs');
const { NCABrowser, isNCAListing } = require('./photo-finder/nca.cjs');
const { MODES, lookupSources } = require('./photo-finder/sources.cjs');
const { openDestination, saveManifest, downloadPhoto } = require('./photo-finder/downloads.cjs');
const { toCSV, notFoundReport } = require('./photo-finder/reports.cjs');


function createPhotoService({runtimePath,onChange=()=>{},browsers,recognizer}) {
let browser, nca, controller, pendingHelp;
let starting = false;
let settings = {};
const state = {
  filename: '', sheets: [], vehicles: [], output: '', running: false,
  help: '', activity: 'Import an auction list to get started.',
  startedAt: null, finishedAt: null,
  sourceMode: 'both', ncaSignedIn: false,
};
const notify = () => onChange();
const activity = message => { state.activity = message; notify(); };
recognizer ||= createViewRecognizer({runtimePath, onMessage: activity});
function requestHelp(message) {
  state.help = message;
  notify();
  return new Promise((resolve, reject) => { pendingHelp = { resolve, reject }; });
}
function settleHelp(kind) {
  if (!pendingHelp) return;
  const help = pendingHelp;
  pendingHelp = null;
  state.help = '';
  if (kind === 'continue') help.resolve();
  else {
    const error = new Error(kind === 'skip' ? 'Skipped by you.' : 'Stopped');
    error.code = kind === 'skip' ? 'SKIPPED' : 'STOPPED';
    help.reject(error);
  }
  notify();
}
async function persistSettings() {
  await fs.mkdir(runtimePath, { recursive: true });
  await fs.writeFile(path.join(runtimePath, 'settings.json'), JSON.stringify(settings, null, 2));
}
async function importFile(file) {
  if (state.running) throw new Error('Stop the current batch before importing another file.');
  const result = await readWorkbook(file);
  state.filename = result.filename;
  state.workbookPath = file;
  state.sheets = result.sheets;
  state.vehicles = result.vehicles;
  state.finishedAt = null;
  const valid = result.vehicles.filter(v => v.status === 'ready').length;
  activity(`${valid} vehicles ready. ${result.vehicles.length - valid} rows need a valid No. or VIN.`);
  return state;
}
function delay(ms, signal) {
  return new Promise((resolve, reject) => {
    const onAbort = () => { clearTimeout(timer); reject(new Error('Stopped')); };
    const timer = setTimeout(() => { signal.removeEventListener('abort', onAbort); resolve(); }, ms);
    signal.addEventListener('abort', onAbort, { once: true });
    if (signal.aborted) onAbort();
  });
}
async function runBatch(mode, id) {
  const rows = state.vehicles.filter(v => v.status !== 'invalid' && (mode !== 'single' || v.id === id) && (mode !== 'retry' || ['error', 'partial', 'not_found', 'skipped', 'stopped'].includes(v.status)));
  if (!rows.length) throw new Error('There are no vehicles to process.');
  const stat = await fs.stat(state.output).catch(() => null);
  if (!stat?.isDirectory()) throw new Error('Choose an existing destination folder first.');
  await fs.access(state.output, require('node:fs').constants.W_OK);
  recognizer.retry?.();
  state.running = true;
  state.startedAt = new Date().toISOString();
  state.finishedAt = null;
  controller = new AbortController();
  const signal = controller.signal;
  browser.signal = signal;
  nca.signal = signal;
  for (const row of rows) {
    row.status = 'queued'; row.message = ''; row.count = 0; row.source = ''; row.missingViews = [];
  }
  notify();
  // The job runs independently; IPC returns immediately so Stop and Continue remain usable.
  void (async () => {
    try {
      for (const row of rows) {
        if (signal.aborted) break;
        row.status = 'searching'; row.message = 'Finding an exact VIN match…'; notify();
        try {
          const listing = await lookupSources({ bidcars: browser, nca }, state.sourceMode, row.vin, signal);
          const photoBrowser = listing.provider === 'nca' ? nca : browser;
          signal.throwIfAborted();
          row.source = listing.source;
          const destination = await openDestination(state.output, row);
          destination.manifest.source = listing.source;
          destination.manifest.provider = listing.provider;
          destination.manifest.updatedAt = new Date().toISOString();
          destination.manifest.expected = listing.images.length;
          destination.manifest.complete = false;
          await saveManifest(destination);
          row.status = 'downloading';
          const files = new Set();
          const failures = [];
          for (let i = 0; i < listing.images.length; i++) {
            signal.throwIfAborted();
            activity(`${row.vin} · photo ${i + 1} of ${listing.images.length}`);
            let saved, error;
            for (let attempt = 0; attempt < 2; attempt++) {
              try {
                saved = await downloadPhoto({ destination, url: listing.images[i], index: i, signal,
                  fetchPhoto: (url, abortSignal) => photoBrowser.fetchPhoto(url, abortSignal) });
                break;
              } catch (e) {
                error = e;
                if (signal.aborted) throw e;
                if (attempt === 0) await delay(1000, signal);
              }
            }
            if (saved) {
              files.add(saved.file);
              const item = destination.manifest.photos.find(p => p.url === listing.images[i]);
              if (item) item.description = [...new Set([item.description, listing.imageDescriptions?.[listing.images[i]]].filter(Boolean))].join(' ').slice(0, 1000);
              await saveManifest(destination);
            }
            else failures.push({ url: listing.images[i], error: error.message });
            row.count = files.size;
            row.message = `${files.size} photos saved${failures.length ? ` · ${failures.length} failed` : ''}`;
            notify();
            await delay(180, signal);
          }
          destination.manifest.complete = failures.length === 0;
          destination.manifest.failures = failures;
          await saveManifest(destination);
          const { verifiedFile } = require('./photo-finder/downloads.cjs');
          row.status = 'classifying';
          row.message = 'Identifying Front, Interior, Side and Rear views…';
          notify();
          const classified = new Map();
          for (const item of destination.manifest.photos) {
            signal.throwIfAborted();
            if (photoView(photoDescription(item.url, item.description)) || item.classification?.version === RECOGNITION_VERSION) continue;
            if (!await verifiedFile(destination.directory, item)) continue;
            activity(`${row.vin} · identifying photo views locally…`);
            if (!classified.has(item.sha256)) classified.set(item.sha256, await recognizer.classify(path.join(destination.directory, item.file), signal));
            const result = classified.get(item.sha256);
            if (result) {
              item.classification = result;
              await saveManifest(destination);
            }
          }
          const selection = await selectPosterPhotos(destination, item => verifiedFile(destination.directory, item));
          row.missingViews = selection.missingViews;
          row.status = failures.length ? (files.size ? 'partial' : 'error') : 'done';
          row.message = failures.length ? `${files.size} saved; ${failures.length} failed. ${failures[0].error}` : `${files.size} photos saved. Ready in your folder.`;
          if (selection.missingViews.length) row.message += ` Select manually: ${selection.missingViews.join(', ')}.`;
          if (recognizer.warning) row.message += ` ${recognizer.warning}`;
        } catch (error) {
          row.status = signal.aborted ? 'stopped' : error.code === 'NOT_FOUND' ? 'not_found' : error.code === 'SKIPPED' ? 'skipped' : 'error';
          row.message = signal.aborted ? 'Stopped. Saved photos will be reused when you retry.' : error.message;
          row.missingViews = ['front', 'interior', 'side', 'rear'];
        }
        notify();
        if (!signal.aborted) await delay(1400, signal);
      }
    } catch (error) {
      if (!signal.aborted) state.activity = error.message;
    } finally {
      for (const row of rows) if (['queued', 'searching', 'downloading', 'classifying'].includes(row.status)) {
        row.status = 'stopped'; row.message = 'Not finished. Retry to continue.';
      }
      state.running = false;
      state.help = '';
      state.finishedAt = new Date().toISOString();
      state.activity = signal.aborted ? 'Batch stopped. Your saved photos are kept.' : 'Batch finished. Review the results below.';
      controller = null;
      browser.signal = null;
      nca.signal = null;
      notify();
    }
  })();
  return state;
}


  async function initialize() {
    try { settings = JSON.parse(await fs.readFile(path.join(runtimePath, 'settings.json'), 'utf8')); } catch {}
    if (!settings || typeof settings !== 'object' || Array.isArray(settings)) settings = {};
    if (typeof settings.output === 'string') state.output = settings.output;
    if (MODES.includes(settings.sourceMode)) state.sourceMode = settings.sourceMode;
    browser = browsers?.bidcars || new BidCarsBrowser({runtimePath: path.join(runtimePath, 'bidcars-session'), onMessage: activity, requestHelp, stopped: () => controller?.signal.aborted || false});
    nca = browsers?.nca || new NCABrowser({runtimePath: path.join(runtimePath, 'nca-session'), onMessage: activity, requestHelp, stopped: () => controller?.signal.aborted || false});
  }
  async function command(action, args = {}) {
    switch (action) {
      case 'import-workbook':
        if (state.running || starting) throw new Error('Stop the batch before importing.');
        await importFile(args.file); break;
      case 'set-output':
        if (state.running || starting) throw new Error('Stop the batch before changing its destination.');
        if (!(await fs.stat(args.directory)).isDirectory()) throw new Error('Choose an existing photo folder.');
        settings.output=state.output=args.directory; await persistSettings(); break;
      case 'choose-workbook': {
        if (state.running || starting) throw new Error('Stop the batch before importing.');
        const result = await dialog.showOpenDialog({title: 'Import auction Excel file', filters: [{name:'Excel workbook',extensions:['xlsx']}], properties:['openFile']});
        if (!result.canceled) await importFile(result.filePaths[0]);
        break;
      }
      case 'choose-output': {
        if (state.running || starting) throw new Error('Stop the batch before changing its destination.');
        const result = await dialog.showOpenDialog({title:'Save vehicle photo folders here', defaultPath:state.output || undefined, properties:['openDirectory','createDirectory']});
        if (!result.canceled) { state.output=result.filePaths[0]; settings.output=state.output; await persistSettings(); }
        break;
      }
      case 'workbook-data':
        if (!state.workbookPath) throw new Error('Choose a workbook first.');
        return {filename:state.filename,bytes:(await fs.readFile(state.workbookPath)).toString('base64')};
      case 'set-source':
        if (state.running || starting) throw new Error('Stop the batch before changing sources.');
        if (!MODES.includes(args.mode)) throw new Error('Choose a supported photo source.');
        settings.sourceMode=state.sourceMode=args.mode; await persistSettings(); break;
      case 'login':
        if (state.running || starting) throw new Error('Stop the batch before signing in, or use the NCA browser.');
        await nca.login(args.email,args.password); state.ncaSignedIn=true; break;
      case 'open-browser': await browser.open(); break;
      case 'open-nca': await nca.open(); break;
      case 'start':
        if (state.running || starting) throw new Error('A batch is already running.');
        if (!['all','retry','single'].includes(args.mode)) throw new Error('Invalid batch mode.');
        starting=true;
        try { await runBatch(args.mode, args.id); } finally { starting=false; }
        break;
      case 'search-one': {
        if (state.running || starting) throw new Error('A batch is already running.');
        const vin = normalizeVIN(args.vin);
        if (!VIN_PATTERN.test(vin)) throw new Error('Enter a complete 17-character VIN (excluding I, O and Q).');
        const requestedNo = String(args.no || '').trim();
        if (requestedNo && (!/^[0-9]+$/.test(requestedNo) || Number(requestedNo) < 1 || !Number.isSafeInteger(Number(requestedNo)))) throw new Error('No. must be a positive whole number.');
        let row = state.vehicles.find(v => v.vin === vin && v.status !== 'invalid' && (!requestedNo || v.no === requestedNo));
        const previousRows = [...state.vehicles];
        if (!row) {
          if (state.vehicles.length >= 5000) throw new Error('Please use at most 5,000 vehicles at a time.');
          const no = requestedNo || String(Math.max(0, ...state.vehicles.map(v => Number(v.no) || 0)) + 1);
          if (!Number.isSafeInteger(Number(no))) throw new Error('Enter a valid vehicle No.');
          row = { id: require('node:crypto').randomUUID(), no, vin, vehicle: '', year: '', folder: `${no}. ${vin}`, status: 'ready', message: '', count: 0, source: '' };
          state.vehicles.push(row);
        }
        starting = true;
        try { await runBatch('single', row.id); }
        catch (error) { state.vehicles = previousRows; throw error; }
        finally { starting = false; }
        break;
      }
      case 'stop': stop(); break;
      case 'continue': settleHelp('continue'); break;
      case 'skip': settleHelp('skip'); break;
      case 'open-folder': {
        if (!state.output) throw new Error('Choose a destination folder first.');
        const row=args.id ? state.vehicles.find(v=>v.id===args.id) : null;
        if (args.id && !row?.folder) throw new Error('Unknown vehicle folder.');
        const error=await shell.openPath(row ? path.join(state.output,row.folder) : state.output);
        if (error) throw new Error(error);
        break;
      }
      case 'open-listing': {
        if (state.running) throw new Error('Wait for the batch to finish.');
        const row=state.vehicles.find(v=>v.id===args.id);
        if (!row || !(isBidCars(row.source)||isNCAListing(row.source))) throw new Error('No verified listing is available.');
        const sourceBrowser=isNCAListing(row.source)?nca:browser;
        await sourceBrowser.load(row.source); sourceBrowser.window.show(); break;
      }
      case 'export-report-data':
      case 'export-not-found-data':
      case 'export-report':
      case 'export-not-found': {
        if (!state.vehicles.length) throw new Error('Import a workbook first.');
        const missing=action.startsWith('export-not-found');
        const report=missing?notFoundReport(state.vehicles):null;
        if (missing && !report.count) throw new Error('No vehicles are marked Not found.');
        const csv=missing?report.csv:toCSV([['No.','VIN','Vehicle','Year','Status','Photos','Folder','Listing','Message'],...state.vehicles.map(v=>[v.no,v.vin,v.vehicle,v.year,v.status,v.count,v.folder,v.source,v.message])]);
        if(action.endsWith('-data')) return {csv};
        const result=await dialog.showSaveDialog({defaultPath:missing?'not-found-vins.csv':'auction-photo-report.csv',filters:[{name:'CSV report',extensions:['csv']}]});
        if (!result.canceled) await fs.writeFile(result.filePath,csv,'utf8');
        break;
      }
      default: throw new Error('Unknown photo action.');
    }
    notify(); return state;
  }
  function stop() { controller?.abort(); browser?.stopNavigation(); nca?.stopNavigation(); settleHelp('stop'); }
  async function posterPhotos(id) {
    const row=state.vehicles.find(v=>v.id===id);
    if (!row?.folder || !state.output) throw new Error('No saved photos for this vehicle.');
    const {verifiedFile}=require('./photo-finder/downloads.cjs');
    const destination=await openDestination(state.output,row);
    const selection = await selectPosterPhotos(destination, async item => {
      if (!await verifiedFile(destination.directory,item)) return null;
      return (await fs.readFile(path.join(destination.directory,item.file))).toString('base64');
    });
    return {vin:row.vin, ...selection};
  }
  return {state, initialize, command, stop, posterPhotos};
}
module.exports={createPhotoService};
