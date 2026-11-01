const {spawn}=require('node:child_process');
const fs=require('node:fs/promises');
const os=require('node:os');
const path=require('node:path');
const readline=require('node:readline');
(async()=>{
  const runtime=await fs.mkdtemp(path.join(os.tmpdir(),'nojoom-smoke-'));
  const env={...process.env};delete env.ELECTRON_RUN_AS_NODE;
  const executable=process.argv[2] || require('electron');
  const child=spawn(executable,[...(process.argv[2]?[]:[path.resolve(__dirname,'..')]),'--runtime',runtime],{env,stdio:['pipe','pipe','pipe']});
  let diagnostics='';child.stderr.on('data',chunk=>diagnostics+=chunk);
  const timeout=setTimeout(()=>{child.kill('SIGKILL');},30000);
  try {
    const handshake=await new Promise((resolve,reject)=>{
      readline.createInterface({input:child.stdout}).on('line',line=>{
        try {const message=JSON.parse(line);if(message.nojoomAutomation) resolve(message);} catch{}
      });
      child.on('error',reject);child.on('exit',code=>reject(new Error(`Helper exited ${code}: ${diagnostics}`)));
    });
    const response=await fetch(`http://127.0.0.1:${handshake.port}/state`,{headers:{Authorization:`Bearer ${handshake.token}`}});
    const state=await response.json();
    if(!response.ok || !Array.isArray(state.photos?.vehicles) || !Array.isArray(state.importer?.vehicles)) throw new Error('Invalid helper state.');
    console.log('Packaged helper started; authenticated native API returned both workspaces.');
    const ExcelJS=require('exceljs');
    const workbook=new ExcelJS.Workbook();
    const sheet=workbook.addWorksheet('Vehicles');
    sheet.addRow(['No.','VIN','Vehicle Type','Year','Primary Price','Green Light']);
    sheet.addRow([1,'JTDKN3DU0B1457686','Prius',2011,0,1200]);
    const file=path.join(runtime,'smoke-vehicles.xlsx');
    await workbook.xlsx.writeFile(file);
    const command=async(action,args={})=>{
      const reply=await fetch(`http://127.0.0.1:${handshake.port}/command`,{method:'POST',headers:{Authorization:`Bearer ${handshake.token}`,'Content-Type':'application/json'},body:JSON.stringify({action,args})});
      const data=await reply.json();if(!reply.ok) throw new Error(data.error);return data;
    };
    const imported=await command('photos.import-workbook',{file});
    if(imported.photos.vehicles.length!==1) throw new Error('Workbook did not reach Photo Finder.');
    await command('photos.set-output',{directory:runtime});
    const csv=await command('photos.export-report-data');
    if(!csv.csv.includes('JTDKN3DU0B1457686')) throw new Error('Report omitted the imported VIN.');
    const shared=await command('photos.workbook-data');
    if(!shared.bytes) throw new Error('Workbook sharing failed.');
    await command('importer.use-workbook');
    const validated=await command('importer.validate');
    if(validated.importer.vehicles.length!==1 || validated.importer.vehicles[0].biddingStart!==0) throw new Error('Shared workbook validation failed.');
    console.log('Workbook import, folder selection, CSV report, workbook sharing and price validation passed without visiting live sites.');

    child.stdin.end();
    await new Promise(resolve=>child.once('exit',resolve));
    console.log('Helper shut down cleanly when its parent connection closed.');
  } finally {clearTimeout(timeout);child.kill();await fs.rm(runtime,{recursive:true,force:true});}
})().catch(error=>{console.error(error.message);process.exitCode=1;});
