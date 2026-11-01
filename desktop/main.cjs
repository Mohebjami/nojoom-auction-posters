const {app,dialog,shell}=require('electron');
const path=require('node:path');
const {randomBytes}=require('node:crypto');
const {createAPI}=require('./api.cjs');
const {createPhotoService}=require('./photo-service.cjs');
app.setName('Nojoom Automation');
const runtime=process.argv[process.argv.indexOf('--runtime')+1];
if(process.argv.includes('--runtime') && runtime) app.setPath('userData',path.resolve(runtime));
app.dock?.hide();
let photos, importer, server, exiting=false;
async function shutdown() {
  if(exiting) return; exiting=true;
  photos?.stop(); await importer?.stop(); server?.close(); app.quit();
}
process.stdin.resume();
process.stdin.on('end',()=>void shutdown());
process.on('SIGTERM',()=>void shutdown());
app.whenReady().then(async()=>{
  const {chromium}=await import('playwright');
  const {createImporterService}=await import('./importer-service.js');
  const runtimePath=app.getPath('userData');
  photos=createPhotoService({runtimePath}); await photos.initialize();
  importer=createImporterService({runtimePath,dialog,shell,chromium});
  const token=randomBytes(32).toString('hex');
  server=await createAPI({token,getState:()=>({photos:photos.state,importer:importer.state}),
    command:async(action,args)=>{
      const [area,name]=action.split('.');
      if(area==='photos') {
        const result=await photos.command(name,args);
        if(name.endsWith('-data')) return result;
      }
      else if(area==='importer') {
        if(name==='use-workbook') {
          if(!photos.state.workbookPath) throw new Error('Choose a photo workbook first.');
          args={file:photos.state.workbookPath};
        }
        await importer.command(name,args);
      } else throw new Error('Unknown action.');
      return {photos:photos.state,importer:importer.state};
    },posterPhotos:id=>photos.posterPhotos(id)});
  process.stdout.write(JSON.stringify({nojoomAutomation:true,port:server.address().port,token})+'\n');
}).catch(error=>{process.stderr.write(error.message+'\n');app.exit(1);});
app.on('window-all-closed',()=>{});
