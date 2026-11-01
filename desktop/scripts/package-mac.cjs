const path=require('node:path');
const fs=require('node:fs/promises');
const {spawnSync}=require('node:child_process');
(async()=>{
  const {packager}=await import('@electron/packager');
  const root=path.resolve(__dirname,'..');
  const bundles=await packager({dir:root,name:'Nojoom Automation',platform:'darwin',arch:process.arch,
    appBundleId:'com.vehicleposter.automation',out:path.join(root,'release'),overwrite:true,
    ignore:[/^\/test(?:\/|$)/,/^\/scripts(?:\/|$)/,/^\/release(?:\/|$)/,/^\/\.runtime(?:\/|$)/,/^\/reports(?:\/|$)/,/^\/\.env/],
    prune:true,asar:false,
  });
  const mainApp=process.argv[2];
  if(mainApp) {
    const resources=path.join(path.resolve(mainApp),'Contents','Resources','nojoom-automation');
    await fs.mkdir(resources,{recursive:true});
    const target=path.join(resources,'Nojoom Automation.app');
    await fs.rm(target,{recursive:true,force:true});
    await fs.cp(path.join(bundles[0],'Nojoom Automation.app'),target,{recursive:true,verbatimSymlinks:true});
    // Re-sign nested code after copying the helper into the Flutter app.
    const signed=spawnSync('codesign',['--force','--deep','--preserve-metadata=entitlements','--sign','-',path.resolve(mainApp)],{stdio:'inherit'});
    if(signed.status!==0) throw new Error('Could not sign the combined app.');
    console.log(`Combined app ready: ${path.resolve(mainApp)}`);
  } else console.log(`Automation helper ready: ${bundles[0]}`);
})().catch(error=>{console.error(error.message);process.exitCode=1;});
