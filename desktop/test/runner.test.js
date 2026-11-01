import test from 'node:test';
import assert from 'node:assert/strict';
import {runVehicles} from '../auction-importer/runner.js';
const vehicle={row:2,vin:'JTDKN3DU0B1457686',biddingStart:1000,greenLight:1200};
const listing={lot:'50172',item:1,start:'$1,000.00',reserve:'$1,200.00',sellType:'On Approval',location:'Afghanistan (Herat NCA Branch)'};
function mock(rows=[]) {
  const calls=[];
  return {calls,
    async findVehicle(){return {lot:'50172'};}, async listings(){return rows;},
    async fill(v,m,item){calls.push(['fill',item]);},async closeModal(){calls.push(['close']);},
    async publish(){calls.push(['publish']);},async verify(){calls.push(['verify']);},
  };
}
test('preview fills and dismisses without publishing or checkpointing',async()=>{
  const auction=mock(); const state={};
  await runVehicles({auction,vehicles:[vehicle],state});
  assert.deepEqual(auction.calls,[['fill',1],['close']]); assert.deepEqual(state,{});
});
test('publish checkpoints before click, then verifies before marking complete',async()=>{
  const auction=mock([{...listing,lot:'99999',item:4}]); const states=[]; const state={};
  await runVehicles({auction,vehicles:[vehicle],publish:true,state,saveState:async s=>states.push(s[vehicle.vin].status)});
  assert.deepEqual(states,['pending','verified']);
  assert.deepEqual(auction.calls,[['fill',5],['publish'],['verify']]);
});
test('a matching existing vehicle is verified and skipped',async()=>{
  const auction=mock([listing]);
  await runVehicles({auction,vehicles:[vehicle],publish:true});
  assert.deepEqual(auction.calls,[['verify']]);
});
test('conflicting existing prices stop before publish',async()=>{
  const auction=mock([{...listing,start:'$99.00'}]);
  await assert.rejects(runVehicles({auction,vehicles:[vehicle],publish:true}),/different values/);
  assert.deepEqual(auction.calls,[]);
});
test('an uncertain prior attempt is never automatically republished',async()=>{
  const auction=mock();
  await assert.rejects(runVehicles({auction,vehicles:[vehicle],publish:true,state:{[vehicle.vin]:{status:'pending'}}}),/No second publish/);
  assert.deepEqual(auction.calls,[]);
});
test('verification failure preserves pending state and stops subsequent rows',async()=>{
  const auction=mock(); auction.verify=async()=>{throw new Error('missing');}; const state={};
  await assert.rejects(runVehicles({auction,vehicles:[vehicle,{...vehicle,row:3}],publish:true,state}),/missing/);
  assert.equal(state[vehicle.vin].status,'pending'); assert.equal(auction.calls.filter(c=>c[0]==='publish').length,1);
});
test('explicit numbering cannot collide with existing items',async()=>{
  const auction=mock([{...listing,lot:'99999',item:4}]);
  await assert.rejects(runVehicles({auction,vehicles:[vehicle],startItem:1,publish:true}),/overlap/);
});
