const { test } = require('node:test');
const assert = require('node:assert/strict');
const { notFoundReport, toCSV } = require('../photo-finder/reports.cjs');
const VIN = 'JTDKN3DU5B0249292';

test('not found export preserves original numbers and VINs and excludes every other outcome', () => {
  const report = notFoundReport([
    ...['done', 'error', 'partial', 'invalid', 'ready', 'queued', 'searching', 'downloading', 'skipped', 'stopped'].map(status => ({ no: '99', vin: 'JTEZU17R868042363', status })),
    { no: '7', vin: VIN, vehicle: 'Prius', year: '2011', status: 'not_found' },
  ]);
  assert.equal(report.count, 1);
  assert.equal(report.csv, '\ufeff"No.","VIN","Vehicle","Year"\r\n"7","JTDKN3DU5B0249292","Prius","2011"');
  assert.ok(!report.csv.includes('JTEZU17R868042363'));
});
test('CSV handles quotes, commas, newlines and formula-like imported text', () => {
  assert.equal(toCSV([['Car, "special"', 'two\nlines', '=1+1', null]]), '\ufeff"Car, ""special""","two\nlines","\'=1+1",""');
});
test('no missing listings yields a zero count and headers only', () => {
  assert.deepEqual(notFoundReport([]), { count: 0, csv: '\ufeff"No.","VIN","Vehicle","Year"' });
});
