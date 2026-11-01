import test from 'node:test';
import assert from 'node:assert/strict';
import ExcelJS from 'exceljs';
import {parseWorksheet, parsePrice, readVehicles} from '../auction-importer/excel.js';

function sheet(rows) {
  const workbook = new ExcelJS.Workbook();
  const sheet = workbook.addWorksheet('Vehicles');
  sheet.addRows(rows);
  return sheet;
}
const vin = 'JTDKN3DU0B1457686';
test('reads reordered headers, normalized VIN, gaps and numeric zero', () => {
  const result = parseWorksheet(sheet([
    ['Auction import'], ['Reserve Price','VIN Number','Starting Bid'],
    ['$1,200.50', ` ${vin.toLowerCase()} `, 0], [],
  ]));
  assert.deepEqual(result, [{row:3,vin,biddingStart:0,greenLight:1200.50}]);
});
test('validates the entire workbook before any browser work', () => {
  assert.throws(() => parseWorksheet(sheet([
    ['VIN','Bidding Start','Green Light'], [vin,1,2], [vin,2,3], ['BAD',4,5],
  ])), /Row 3: Duplicate VIN[\s\S]*Row 4: VIN must/);
});
test('missing price differs from zero, and malformed amounts fail', () => {
  for (const value of ['',null,undefined,-1,'1,20','1e3','12.345',Infinity]) assert.throws(()=>parsePrice(value,'Price'));
  assert.equal(parsePrice(0,'Price'),0);
  assert.equal(parsePrice('1,200.25','Price'),1200.25);
});
test('requires cached formula results and rejects Excel errors', () => {
  assert.throws(()=>parseWorksheet(sheet([['VIN','Bidding Start','Green Light'],[vin,{formula:'1+2'},4]])),/cached result/);
  assert.throws(()=>parseWorksheet(sheet([['VIN','Bidding Start','Green Light'],[vin,{error:'#VALUE!'},4]])),/Excel error/);
  assert.equal(parseWorksheet(sheet([['VIN','Bidding Start','Green Light'],[vin,{formula:'1+2',result:3},4]]))[0].biddingStart,3);
});
test('input template has usable columns and no invented vehicles', async () => {
  await assert.rejects(readVehicles(new URL('../templates/vehicles.xlsx',import.meta.url).pathname), /contains no vehicles/);
});
test('reads Primary Price and prefers Green Light over Red Light with multiline headers', () => {
  const result = parseWorksheet(sheet([
    ['Seventh Round Auction List'], ['Date: 20/10/2026'],
    ['No.', 'VIN', 'Primary\nPrice', 'Red\nLight', 'Green\nLight'],
    [1, vin, 6900, 6500, 7000],
    [2, '1HGCM82633A004352', 5000, 6000, null],
    [3, '1FTFW1ET1EFA00001', 4000, 4500, '   '],
  ]));
  assert.deepEqual(result, [
    {row:4,vin,biddingStart:6900,greenLight:7000},
    {row:5,vin:'1HGCM82633A004352',biddingStart:5000,greenLight:6000},
    {row:6,vin:'1FTFW1ET1EFA00001',biddingStart:4000,greenLight:4500},
  ]);
});
test('zero Green Light is a real value and does not fall back to Red Light', () => {
  const result = parseWorksheet(sheet([['VIN','Primary Price','Red Light','Green Light'],[vin,100,200,0]]));
  assert.equal(result[0].greenLight,0);
});
test('accepts a Red Light column when the Green Light column is absent', () => {
  const result = parseWorksheet(sheet([['VIN','Primary Price','Red Light'],[vin,100,200]]));
  assert.equal(result[0].greenLight,200);
});
test('uses Red Light for blank Primary Price and retains Green Light for reserve', () => {
  const result = parseWorksheet(sheet([['VIN','Primary Price','Red Light','Green Light'],[vin,null,200,300]]));
  assert.deepEqual(result,[{row:2,vin,biddingStart:200,greenLight:300}]);
  const redOnly = parseWorksheet(sheet([['VIN','Primary Price','Red Light','Green Light'],[vin,' ',200,null]]));
  assert.deepEqual(redOnly,[{row:2,vin,biddingStart:200,greenLight:200}]);
  const zero = parseWorksheet(sheet([['VIN','Primary Price','Red Light','Green Light'],[vin,0,200,300]]));
  assert.equal(zero[0].biddingStart,0);
});
test('requires Red Light when Primary Price is blank and does not hide invalid prices', () => {
  assert.throws(()=>parseWorksheet(sheet([['VIN','Primary Price','Red Light','Green Light'],[vin,null,null,300]])),/Primary Price \/ Bidding Start \(or Red Light when blank\) is required/);
  assert.throws(()=>parseWorksheet(sheet([['VIN','Primary Price','Red Light','Green Light'],[vin,'invalid',200,300]])),/must be a non-negative amount/);
});
test('requires a reserve amount from Green Light or Red Light', () => {
  assert.throws(()=>parseWorksheet(sheet([['VIN','Primary Price','Red Light','Green Light'],[vin,100,null,null]])),/Green Light \(or Red Light when Green Light is blank\) is required/);
});
test('skips unnumbered summaries but still rejects numbered vehicles without a VIN', () => {
  const rows = [['No.','VIN','Primary Price','Red Light','Green Light'],[1,vin,100,200,null],[],[null,'Total Cars']];
  assert.equal(parseWorksheet(sheet(rows)).length,1);
  rows.splice(2,0,[2,null,100,200,null]);
  assert.throws(()=>parseWorksheet(sheet(rows)),/Row 3: VIN must/);
});
