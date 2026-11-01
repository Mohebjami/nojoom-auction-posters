const fs = require('node:fs/promises');
const path = require('node:path');

const normalizeHeader = value => String(value ?? '').toLowerCase().replace(/[^a-z0-9]/g, '');
const normalizeVIN = value => String(value ?? '').trim().replace(/\s/g, '').toUpperCase();
const VIN_PATTERN = /^[A-HJ-NPR-Z0-9]{17}$/;

function parseSheets(sheets) {
  const vehicles = [];
  const matchedSheets = [];
  const folders = new Set();
  for (const sheet of sheets) {
    const data = sheet.data || [];
    const headerIndex = data.findIndex(row => {
      const headers = row.map(normalizeHeader);
      return headers.includes('vin') && headers.some(h => ['no', 'number', 'sno', 'serialno'].includes(h));
    });
    if (headerIndex < 0) continue;
    const headers = data[headerIndex].map(normalizeHeader);
    const noCol = headers.findIndex(h => ['no', 'number', 'sno', 'serialno'].includes(h));
    const vinCol = headers.indexOf('vin');
    const typeCol = headers.findIndex(h => ['vehicletype', 'vehicle', 'model', 'makeandmodel'].includes(h));
    const yearCol = headers.indexOf('year');
    matchedSheets.push({ name: sheet.sheet, headerRow: headerIndex + 1 });
    for (let i = headerIndex + 1; i < data.length; i++) {
      const row = data[i];
      const no = String(row[noCol] ?? '').trim();
      const vin = normalizeVIN(row[vinCol]);
      if (!no && !vin) continue;
      // Notes and totals below the table occupy the VIN column in the supplied file.
      if (!no && !VIN_PATTERN.test(vin)) continue;
      // Repeated print headers are not vehicle records.
      if (normalizeHeader(no) === 'no' && normalizeHeader(vin) === 'vin') continue;
      let error = '';
      if (!/^[0-9]+$/.test(no) || Number(no) < 1 || !Number.isSafeInteger(Number(no))) error = 'No. must be a positive whole number.';
      else if (!VIN_PATTERN.test(vin)) error = 'VIN must contain 17 letters or digits (excluding I, O and Q).';
      const folder = error ? '' : `${no}. ${vin}`;
      if (folder && folders.has(folder)) error = 'Duplicate No. and VIN; this folder is already listed.';
      if (!error) folders.add(folder);
      vehicles.push({
        id: `${matchedSheets.length}:${i + 1}`,
        no, vin, vehicle: typeCol >= 0 ? String(row[typeCol] ?? '').trim() : '',
        year: yearCol >= 0 ? String(row[yearCol] ?? '').trim() : '',
        sheet: sheet.sheet, row: i + 1, folder,
        status: error ? 'invalid' : 'ready', message: error,
        count: 0, source: '',
      });
    }
  }
  if (!matchedSheets.length) throw new Error('No table with No. and VIN headers was found. Headers may appear below a title, as in your auction file.');
  if (!vehicles.length) throw new Error('The No. and VIN table is empty.');
  if (vehicles.length > 5000) throw new Error('Please import at most 5,000 vehicles at a time.');
  return { vehicles, sheets: matchedSheets };
}

async function readWorkbook(file) {
  if (path.extname(file).toLowerCase() !== '.xlsx') throw new Error('Please select an Excel .xlsx file.');
  const stat = await fs.stat(file);
  if (stat.size > 20 * 1024 * 1024) throw new Error('Please use an Excel file smaller than 20 MB.');
  const reader = require('read-excel-file/node');
  const readExcelFile = reader.default || reader;
  return { ...parseSheets(await readExcelFile(file)), filename: path.basename(file) };
}

module.exports = { parseSheets, readWorkbook, normalizeVIN, VIN_PATTERN };
