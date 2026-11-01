import fs from 'node:fs/promises';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {readVehicles} from './auction-importer/excel.js';
import {NcaAuction} from './auction-importer/auction.js';
import {runVehicles} from './auction-importer/runner.js';

export function auctionURL(value) {
  const url = new URL(value);
  if (url.origin !== 'https://my.nca.af' || !/^\/auction\/view\/[A-Za-z0-9_-]+\/?$/.test(url.pathname) || url.username || url.password) {
    throw new Error('Use an https://my.nca.af/auction/view/... auction URL.');
  }
  url.search=''; url.hash=''; return url.href;
}
export function positive(value, name) {
  if (value === undefined || value === null || value === '') return undefined;
  if (!/^\d+$/.test(String(value)) || !Number.isSafeInteger(Number(value)) || Number(value)<1) throw new Error(`${name} must be a positive whole number.`);
  return Number(value);
}
const hash = value => createHash('sha256').update(value).digest('hex');
export async function writeJson(file,value) {
  const temp=`${file}.tmp`;
  await fs.writeFile(temp,JSON.stringify(value,null,2)+'\n',{mode:0o600});
  await fs.rename(temp,file);
}
export function createImporterService({runtimePath,dialog,shell,chromium,onChange=()=>{}}) {
  const state={file:'',filename:'',vehicles:[],running:false,status:'ready',mode:'',results:[],message:'Choose a workbook, validate it, then preview the auction forms.',reportDirectory:'',auctionURL:'',browserOpen:false};
  let browser, job, validation, stopping=false;
  function idle() { if (state.running) throw new Error('Stop the current import first.'); }
  async function select(file) {
    idle(); validation=null;
    state.file=file; state.filename=path.basename(file); state.vehicles=[]; state.results=[]; state.status='ready';
    state.message='Validate the workbook before opening the website.';
  }
  async function validate(args) {
    idle(); validation=null; state.vehicles=[];
    if (!state.file) throw new Error('Choose a workbook first.');
    const all=await readVehicles(state.file,args.sheet || undefined);
    const limit=positive(args.limit,'Limit');
    const startItem=positive(args.startItem,'First item');
    const vehicles=limit===undefined?all:all.slice(0,limit);
    const fingerprint=hash(await fs.readFile(state.file));
    validation={fingerprint,vehicles,sheet:args.sheet || '',limit,startItem};
    state.vehicles=vehicles; state.status='validated';
    state.message=`Validated ${all.length} vehicles; selected ${vehicles.length}. Preview fills forms without publishing.`;
  }
  async function start(args) {
    idle();
    if (!['preview','publish'].includes(args.mode)) throw new Error('Choose Preview or Publish.');
    if (!validation || hash(await fs.readFile(state.file))!==validation.fingerprint) {
      validation=null; state.vehicles=[]; state.status='ready';
      throw new Error('The workbook changed or has not been validated. Validate it again.');
    }
    const url=auctionURL(args.url);
    if (typeof args.email!=='string' || !args.email.trim() || typeof args.password!=='string' || !args.password) throw new Error('Enter your NCA email and password.');
    if (args.mode==='publish' && args.confirmed!==true) throw new Error('Review and confirm publishing first.');
    await browser?.close(); browser=null; stopping=false;
    const selected=validation;
    state.running=true; state.browserOpen=false; state.status='running'; state.mode=args.mode; state.results=[]; state.auctionURL=url; state.message=`${args.mode==='publish'?'Publishing':'Previewing'} ${selected.vehicles.length} vehicles…`;
    // Return immediately. Stop remains available while browser operations are pending.
    job=run({url,selected,publish:args.mode==='publish',email:args.email,password:args.password}).catch(error=>{
      state.status=stopping?'stopped':'failed'; state.message=stopping?'Stopped. Check the report before retrying any pending publish.':error.message;
    }).finally(()=>{state.running=false; onChange();});
  }
  async function run({url,selected,publish,email,password}) {
    const directory=path.join(runtimePath,'reports',`auction-${hash(url).slice(0,16)}`);
    await fs.mkdir(directory,{recursive:true,mode:0o700});
    const lockFile=path.join(directory,'import.lock');
    let lock;
    try { lock=await fs.open(lockFile,'wx',0o600); }
    catch(error) { if(error.code==='EEXIST') throw new Error(`Another run may be active. Inspect the previous process before removing ${lockFile}.`); throw error; }
    const runDirectory=path.join(directory,new Date().toISOString().replace(/[:.]/g,'-'));
    const stateFile=path.join(directory,'state.json');
    const report={auction:url,file:state.file,mode:publish?'publish':'preview',startedAt:new Date().toISOString(),selected:selected.vehicles.length,results:[]};
    let page;
    try {
      await lock.writeFile(JSON.stringify({pid:process.pid,startedAt:report.startedAt}));
      await fs.mkdir(runDirectory,{mode:0o700}); state.reportDirectory=runDirectory;
      let checkpoint={};
      try { checkpoint=JSON.parse(await fs.readFile(stateFile,'utf8')); } catch(error) { if(error.code!=='ENOENT') throw error; }
      if(stopping) throw new Error('Stopped');
      browser=await chromium.launch({headless:false,channel:'chrome'});
      state.browserOpen=true;
      browser.on('disconnected',()=>{state.browserOpen=false;onChange();});
      if(stopping) throw new Error('Stopped');
      const context=await browser.newContext({viewport:{width:1440,height:1000}});
      page=await context.newPage();
      const auction=new NcaAuction(page,url,30000);
      await auction.login(email,password); password='';
      await runVehicles({auction,vehicles:selected.vehicles,publish,startItem:selected.startItem,state:checkpoint,
        saveState:value=>writeJson(stateFile,value),
        capture:async(vehicle,item,stage)=>{await page.screenshot({path:path.join(runDirectory,`${item}-${vehicle.vin}-${stage}.png`),fullPage:true});},
        record:async result=>{report.results.push(result);state.results=[...report.results];state.message=`${result.status} · ${result.vin}${result.error?` · ${result.error}`:''}`;await writeJson(path.join(runDirectory,'report.json'),report);onChange();},
      });
      await auction.open(); await auction.listTable.scrollIntoViewIfNeeded();
      report.status='complete'; state.status='complete';
      const count=status=>report.results.filter(v=>v.status===status).length;
      state.message=`Complete. ${count('published')} published and verified; ${count('already-present')} already present; ${count('preview')} previewed. Chrome stays open for review.`;
    } catch(error) {
      report.status=stopping?'stopped':'failed'; report.error=error.message;
      if(page && !page.isClosed()) await page.screenshot({path:path.join(runDirectory,'error.png'),fullPage:true}).catch(()=>{});
      throw error;
    } finally {
      password=''; if(stopping) await browser?.close(); report.finishedAt=new Date().toISOString(); report.unprocessed=report.selected-report.results.length;
      try { await writeJson(path.join(runDirectory,'report.json'),report); }
      finally {await lock.close();await fs.unlink(lockFile);}
    }
  }
  async function stop() {
    stopping=true; await browser?.close();
    await job; state.browserOpen=false;
  }
  async function command(action,args={}) {
    switch(action) {
      case 'choose-workbook': {
        idle(); const result=await dialog.showOpenDialog({title:'Choose NCA auction workbook',filters:[{name:'Excel or CSV',extensions:['xlsx','csv']}],properties:['openFile']});
        if(!result.canceled) await select(result.filePaths[0]); break;
      }
      case 'use-workbook':
      case 'use-file': await select(args.file); break;
      case 'validate': await validate(args); break;
      case 'start': await start(args); break;
      case 'stop': await stop(); break;
      case 'close-browser': idle(); await browser?.close(); state.browserOpen=false; break;
      case 'open-reports':
        if(!state.reportDirectory) throw new Error('No report is available yet.');
        {const error=await shell.openPath(state.reportDirectory); if(error) throw new Error(error);} break;
      default: throw new Error('Unknown importer action.');
    }
    onChange(); return state;
  }
  return {state,command,stop};
}
