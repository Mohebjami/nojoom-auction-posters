import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import {chromium} from 'playwright';
import {NcaAuction} from '../auction-importer/auction.js';
import {runVehicles} from '../auction-importer/runner.js';

const vehicles = [
  {row:2,vin:'JTDKN3DU0B1457686',biddingStart:1000,greenLight:1200},
  {row:3,vin:'1HGCM82633A004352',biddingStart:2000,greenLight:2500},
  {row:4,vin:'1FTFW1ET1EFA00001',biddingStart:3000,greenLight:3500},
];

function fixture() {
  const state = {list:[], requests:[], reject:false, omit:false};
  const field = (id,label,type='input') => `<label for="modal_push_auction_${id}">${label}</label><${type} id="modal_push_auction_${id}">${type==='textarea'?'</textarea>':''}`;
  const server = http.createServer(async (request,response) => {
    const url = new URL(request.url,'http://localhost');
    if (url.pathname === '/livewire/update') {
      let text=''; for await(const chunk of request) text+=chunk;
      const data=JSON.parse(text).components[0].calls[0].params[0];
      state.requests.push(data);
      if (!state.reject && !state.omit) state.list.push(data);
      response.setHeader('Content-Type','application/json');
      response.end(JSON.stringify({components:[{effects:{returns:[{status:state.reject?'error':'success',message:state.reject?'Rejected by fixture':undefined}]}}]}));
      return;
    }
    response.setHeader('Content-Type','text/html');
    if (url.pathname === '/login') {
      response.end('<form action="/dashboard"><input placeholder="you@example.com"><input placeholder="Enter your password" type="password"><button>Sign in Signing in…</button></form>');
      return;
    }
    if (url.pathname.startsWith('/inventory/view/vehicle/')) {
      const index=Number(url.pathname.split('/').at(-1));
      response.end(`<table><tr><td>VIN</td><td>${vehicles[index].vin}</td></tr></table>`);
      return;
    }
    if (!url.pathname.startsWith('/auction/view/')) {response.end('<p>Dashboard</p>');return;}
    const search=url.searchParams.get('auctionSearch');
    const candidates=vehicles.map((v,index)=>({...v,index})).filter(v=>v.vin===search);
    response.end(`<!doctype html><html><body>
      <table><thead><tr><th>Lot Details</th><th>Lot</th><th>Assign Auction</th></tr></thead><tbody>
      ${candidates.map(v=>`<tr><td><a href="/inventory/view/vehicle/${v.index}">Vehicle ${v.index}</a></td><td>Lot #: ${50172+v.index}</td><td><a aria-label="Add to Auction" onclick="openModal(${v.index})">+</a></td></tr>`).join('')}
      </tbody></table>
      <div style="height:1100px"></div><h5>Auction List</h5>
      <table><thead><tr>${['Item','Lot#','Vehicle','Buy Now','Reserve','Starting Bid','Sell Type','Sell Location','Auction Time','Action'].map(s=>`<th>${s}</th>`).join('')}</tr></thead><tbody>
      ${state.list.map(row=>`<tr><td>${row.item}</td><td>${row.lot}</td><td>Vehicle</td><td></td><td>$${Number(row.green_price).toFixed(2)}</td><td>$${Number(row.bidding_start).toFixed(2)}</td><td>${row.sell_type}</td><td>Afghanistan (${row.towed_from})</td><td>2026-10-20</td><td>Edit</td></tr>`).join('')}
      </tbody></table>
      <div id="modal-push-to-auction" role="dialog" style="display:none;position:fixed;inset:0;background:#0007;overflow:auto" onclick="if(event.target===this)this.style.display='none'">
      <div style="margin:40px auto;background:white;padding:25px;width:500px">
      ${field('item','Item #')}
      <label for="modal_push_auction_branch_id">Sales Branch</label><select id="modal_push_auction_branch_id"><option value="3">Afghanistan</option></select>
      ${field('towed_from','Towed From (Location)')}${field('shipping_cost','Shipping &amp; Clearance Cost')}
      <label for="modal_push_auction_sell_type">Sell Type</label><select id="modal_push_auction_sell_type"><option value="">Select Sell Type</option><option>On Approval</option></select>
      ${field('bidding_start','Bidding Start')}${field('green_price','Green Light')}${field('buy_now','Buy Now')}${field('seller_note','Seller Note (Optional)','textarea')}
      <button onclick="publish()">Yes, Publish</button></div></div>
      <script>
      let index;
      function openModal(value){index=value; document.getElementById('modal-push-to-auction').style.display='block';}
      async function publish(){
        const row={lot:String(50172+index)};
        for(const name of ['item','branch_id','towed_from','shipping_cost','sell_type','bidding_start','green_price','buy_now','seller_note'])row[name]=document.getElementById('modal_push_auction_'+name).value;
        const response=await fetch('/livewire/update',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({components:[{calls:[{method:'modalPushAuction',params:[row]}]}]})});
        await response.json();
      }
      </script></body></html>`);
  });
  return {server,state};
}

test('real browser: publish serially, verify reload, skip duplicates, preview, reject and retain uncertain attempts', {timeout:60000}, async t => {
  const {server,state:site}=fixture();
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  t.after(()=>new Promise(resolve=>server.close(resolve)));
  const browser=await chromium.launch({headless:true,...(process.env.PW_TEST_CHANNEL?{channel:process.env.PW_TEST_CHANNEL}:{})});
  t.after(()=>browser.close());
  const context=await browser.newContext({viewport:{width:1440,height:1000}});
  const page=await context.newPage();
  const auction=new NcaAuction(page,`http://127.0.0.1:${server.address().port}/auction/view/test`,5000);
  await auction.login('local@example.com','local-test');
  const state={}; const results=[];
  await runVehicles({auction,vehicles:vehicles.slice(0,2),publish:true,state,record:async row=>results.push(row)});
  assert.deepEqual(results.map(r=>[r.item,r.status]),[[1,'published'],[2,'published']]);
  assert.deepEqual(site.list.map(row=>row.item),['1','2']);
  assert.equal(site.requests.length,2);
  for(const row of site.list) {
    assert.equal(row.towed_from,'Herat NCA Branch'); assert.equal(row.sell_type,'On Approval');
    assert.equal(row.branch_id,'3'); assert.equal(row.shipping_cost,'0'); assert.equal(row.buy_now,'');
  }
  await runVehicles({auction,vehicles:vehicles.slice(0,2),publish:true,state});
  assert.equal(site.requests.length,2,'rerun must not publish duplicates');
  const preview=[];
  await runVehicles({auction,vehicles:[vehicles[2]],record:async row=>preview.push(row)});
  assert.equal(preview[0].item,3); assert.equal(site.requests.length,2);
  assert.equal(await auction.modal.isVisible(),false);
  site.reject=true;
  const rejectedState={};
  await assert.rejects(runVehicles({auction,vehicles:[vehicles[2]],publish:true,state:rejectedState}),/Rejected by fixture/);
  assert.equal(rejectedState[vehicles[2].vin].status,'pending');
  assert.equal(site.list.length,2);
  site.reject=false; site.omit=true;
  const uncertainState={};
  await assert.rejects(runVehicles({auction,vehicles:[vehicles[2]],publish:true,state:uncertainState}),/not present exactly once/);
  assert.equal(uncertainState[vehicles[2].vin].status,'pending');
  const before=site.requests.length;
  await assert.rejects(runVehicles({auction,vehicles:[vehicles[2]],publish:true,state:uncertainState}),/No second publish/);
  assert.equal(site.requests.length,before);
});
