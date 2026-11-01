// Local installation preserves the previous application and copies checkpoint
// files separately. Runtime data is never added to the distributable bundle.
const fs=require('node:fs/promises');
const path=require('node:path');
const os=require('node:os');
const {execFileSync}=require('node:child_process');
(async()=>{
  const project=path.resolve(__dirname,'../..');
  const source=path.join(project,'build/nojoom/Nojoom Auction Posters.app');
  const target=process.argv[2] || '/Applications/vehicle_poster.app';
  const stamp=new Date().toISOString().replace(/[:.]/g,'-');
  const staged=path.join(path.dirname(target),`Nojoom-update-${stamp}.app`);
  const backup=path.join(project,'build/previous-installed',`vehicle_poster-${stamp}.app`);
  execFileSync('codesign',['--verify','--deep','--strict',source],{stdio:'inherit'});
  const legacyReports=path.resolve(project,'../auto-create-seleslist/reports');
  const runtime=path.join(os.homedir(),'Library/Application Support/com.vehicleposter.vehiclePoster/automation/reports');
  let checkpoints=0;
  for(const folder of await fs.readdir(legacyReports,{withFileTypes:true}).catch(error=>{if(error.code==='ENOENT') return [];throw error;})) {
    if(!folder.isDirectory() || !/^auction-[a-f0-9]{16}$/.test(folder.name)) continue;
    const from=path.join(legacyReports,folder.name);
    try {await fs.access(path.join(from,'import.lock'));throw new Error('Close the older importer before installing. A lock is present.');}
    catch(error){if(error.code!=='ENOENT') throw error;}
    const input=path.join(from,'state.json');
    let checkpoint;
    try{checkpoint=await fs.readFile(input,'utf8');JSON.parse(checkpoint);}catch(error){if(error.code==='ENOENT') continue;throw error;}
    const destination=path.join(runtime,folder.name);await fs.mkdir(destination,{recursive:true,mode:0o700});
    // Existing combined-app state always wins; never overwrite it on an update.
    try{await fs.writeFile(path.join(destination,'state.json'),checkpoint,{flag:'wx',mode:0o600});checkpoints++;}
    catch(error){if(error.code!=='EEXIST') throw error;}
  }
  execFileSync('ditto',[source,staged],{stdio:'inherit'});
  execFileSync('codesign',['--verify','--deep','--strict',staged],{stdio:'inherit'});
  await fs.mkdir(path.dirname(backup),{recursive:true});
  let hadPrevious=false;
  try{await fs.rename(target,backup);hadPrevious=true;}catch(error){if(error.code!=='ENOENT') throw error;}
  try{await fs.rename(staged,target);}catch(error){if(hadPrevious) await fs.rename(backup,target);throw error;}
  console.log(`Installed combined app: ${target}`);
  if(hadPrevious) console.log(`Previous app retained: ${backup}`);
  console.log(`Copied ${checkpoints} previous auction checkpoint files; originals kept.`);
})().catch(error=>{console.error(error.message);process.exitCode=1;});
