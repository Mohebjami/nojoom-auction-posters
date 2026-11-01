import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {auctionURL,positive,createImporterService} from '../importer-service.js';

test('auction and numbering inputs stay restricted',()=>{
  assert.equal(auctionURL('https://my.nca.af/auction/view/abc?search=x#section'),'https://my.nca.af/auction/view/abc');
  for(const url of ['https://evil.example/auction/view/abc','http://my.nca.af/auction/view/abc','https://user:pass@my.nca.af/auction/view/abc','https://my.nca.af/dashboard']) assert.throws(()=>auctionURL(url));
  assert.equal(positive('','Limit'),undefined);
  assert.equal(positive('20','Limit'),20);
  for(const value of ['0','-1','2.5','1e3']) assert.throws(()=>positive(value,'Limit'));
});
test('validation is local; changed workbooks and unconfirmed publishing never launch a browser',async t=>{
  const root=await fs.mkdtemp(path.join(os.tmpdir(),'nojoom-importer-'));
  t.after(()=>fs.rm(root,{recursive:true,force:true}));
  const file=path.join(root,'vehicles.csv');
  const csv='VIN,Primary Price,Green Light\nJTDKN3DU0B1457686,0,1200\n';
  await fs.writeFile(file,csv);
  let launches=0;
  const importer=createImporterService({runtimePath:root,dialog:{},shell:{},chromium:{launch:()=>{launches++;throw new Error('Do not launch.');}}});
  await importer.command('use-workbook',{file});
  const run={mode:'publish',url:'https://my.nca.af/auction/view/abc',email:'test@example.com',password:'secret'};
  await assert.rejects(importer.command('start',run),/validated/);
  await importer.command('validate',{});
  assert.equal(importer.state.vehicles[0].biddingStart,0);
  await assert.rejects(importer.command('start',run),/confirm/);
  await fs.appendFile(file,'1HGCM82633A004352,200,300\n');
  await assert.rejects(importer.command('start',{...run,confirmed:true}),/changed/);
  assert.equal(launches,0);
  await fs.writeFile(file,csv);
  await importer.command('validate',{});
  await assert.rejects(importer.command('validate',{limit:'-1'}),/positive/);
  await assert.rejects(importer.command('start',{...run,confirmed:true}),/validated/);
  assert.equal(JSON.stringify(importer.state).includes('secret'),false);
});
