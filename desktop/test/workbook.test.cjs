const { test } = require('node:test');
const assert = require('node:assert/strict');
const { parseSheets, normalizeVIN } = require('../photo-finder/workbook.cjs');
const VIN = 'JTDKN3DU5B0249292';

test('auction layout: titles above row 3, blanks, notes, and unrelated sheet', () => {
  const result = parseSheets([
    { sheet: 'Sheet1', data: [['Eighth Round Auction List'], ['Date: 27/10/2026'], ['No.', 'VIN', 'Vehicle Type', 'Year'], [1, VIN, 'Prius', 2011], [2, null], [], [null, 'Total Cars']] },
    { sheet: 'Other', data: [['Unrelated data']] },
  ]);
  assert.deepEqual(result.sheets, [{ name: 'Sheet1', headerRow: 3 }]);
  assert.equal(result.vehicles.length, 2);
  assert.equal(result.vehicles[0].folder, `1. ${VIN}`);
  assert.equal(result.vehicles[0].year, '2011');
  assert.equal(result.vehicles[1].status, 'invalid');
});
test('normalizes VIN casing and whitespace', () => {
  assert.equal(normalizeVIN(' jtdkn3du5b0249292\n'), VIN);
});
test('rejects unsafe numbers, malformed VINs, and duplicate folders', () => {
  const result = parseSheets([{ sheet: 'Cars', data: [['No.', 'VIN'], [1, VIN], [1, VIN], ['../escape', VIN], [3, 'INVALID'], [4, VIN.replace('J', 'I')]] }]);
  assert.equal(result.vehicles[0].status, 'ready');
  assert.ok(result.vehicles.slice(1).every(v => v.status === 'invalid'));
  assert.match(result.vehicles[1].message, /Duplicate/);
});
test('same VIN with different auction numbers has separate folders', () => {
  const result = parseSheets([{ sheet: 'Cars', data: [['No.', 'VIN'], [1, VIN], [2, VIN]] }]);
  assert.deepEqual(result.vehicles.map(v => v.folder), [`1. ${VIN}`, `2. ${VIN}`]);
});
test('missing required headers produces a useful error', () => {
  assert.throws(() => parseSheets([{ sheet: 'Wrong', data: [['VIN'], [VIN]] }]), /No\. and VIN headers/);
});
