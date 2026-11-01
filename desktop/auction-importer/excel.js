import ExcelJS from 'exceljs';
import path from 'node:path';

const normalize = value => String(value ?? '').toLowerCase().replace(/[^a-z0-9]/g, '');
const aliases = {
  vin: ['vin', 'vinnumber', 'vehicleidentificationnumber'],
  biddingStart: ['biddingstart', 'startingbid', 'startbid', 'biddingstartprice', 'primaryprice'],
  greenLight: ['greenlight', 'greenprice', 'reserve', 'reserveprice'],
  redLight: ['redlight', 'redprice'],
  recordNumber: ['no', 'sno', 'serialno', 'serialnumber'],
};
const isBlank = value => value == null || String(value).trim() === '';
const isVin = value => /^[A-HJ-NPR-Z0-9]{17}$/.test(value);

function scalar(value) {
  if (value && typeof value === 'object') {
    if ('formula' in value || 'sharedFormula' in value) {
      if (value.result === undefined) throw new Error('Formula has no cached result. Recalculate and save in Excel first.');
      return scalar(value.result);
    }
    if ('error' in value) throw new Error(`Excel error: ${value.error}`);
    if (value.richText) return value.richText.map(part => part.text).join('');
    if ('text' in value) return value.text;
    throw new Error('Unsupported cell value. Use plain text or a number.');
  }
  return value;
}

export function parsePrice(value, label) {
  if (value === null || value === undefined || String(value).trim() === '') throw new Error(`${label} is required (zero is allowed).`);
  let text = String(value).trim().replace(/^\$\s*/, '');
  if (!/^(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d{1,2})?$/.test(text)) {
    throw new Error(`${label} must be a non-negative amount with at most 2 decimals.`);
  }
  text = text.replaceAll(',', '');
  const number = Number(text);
  if (!Number.isFinite(number) || number > Number.MAX_SAFE_INTEGER / 100) throw new Error(`${label} is too large.`);
  return number;
}

export function parseWorksheet(sheet) {
  let columns;
  let headerRow;
  for (let rowNumber = 1; rowNumber <= Math.min(sheet.rowCount, 30); rowNumber++) {
    const found = {};
    sheet.getRow(rowNumber).eachCell((cell, col) => {
      const key = normalize(scalar(cell.value));
      for (const [field, names] of Object.entries(aliases)) {
        if (names.includes(key)) {
          if (found[field]) throw new Error(`Duplicate ${field} column in row ${rowNumber}.`);
          found[field] = col;
        }
      }
    });
    if (found.vin && found.biddingStart && (found.greenLight || found.redLight)) { columns = found; headerRow = rowNumber; break; }
  }
  if (!columns) throw new Error('Missing headers: VIN, Primary Price (or Bidding Start), and Green Light or Red Light. Headers must be in the first 30 rows.');
  const vehicles = [];
  const seen = new Set();
  const errors = [];
  for (let rowNumber = headerRow + 1; rowNumber <= sheet.rowCount; rowNumber++) {
    try {
      const row = sheet.getRow(rowNumber);
      const values = Object.fromEntries(Object.entries(columns).map(([key, col]) => [key, scalar(row.getCell(col).value)]));
      if (Object.values(values).every(isBlank)) continue;
      const vin = String(values.vin ?? '').trim().toUpperCase();
      // Numbered record sheets can include summaries below the vehicle table.
      // Only unnumbered text with no VIN or prices is a footer, never a vehicle.
      if (columns.recordNumber && isBlank(values.recordNumber) && !isVin(vin) &&
          [values.biddingStart, values.greenLight, values.redLight].every(isBlank)) continue;
      if (!isVin(vin)) throw new Error('VIN must contain 17 letters/digits (I, O and Q are not valid VIN characters).');
      if (seen.has(vin)) throw new Error(`Duplicate VIN ${vin}.`);
      seen.add(vin);
      const biddingStart = isBlank(values.biddingStart) ? values.redLight : values.biddingStart;
      const reserve = isBlank(values.greenLight) ? values.redLight : values.greenLight;
      vehicles.push({row: rowNumber, vin,
        biddingStart: parsePrice(biddingStart, 'Primary Price / Bidding Start (or Red Light when blank)'),
        greenLight: parsePrice(reserve, 'Green Light (or Red Light when Green Light is blank)'),
      });
    } catch (error) { errors.push(`Row ${rowNumber}: ${error.message}`); }
  }
  if (errors.length) throw new Error(`Fix the spreadsheet before importing:\n${errors.join('\n')}`);
  if (!vehicles.length) throw new Error('The spreadsheet contains no vehicles. Add your VINs and prices below the headers.');
  return vehicles;
}

export async function readVehicles(file, sheetName) {
  const workbook = new ExcelJS.Workbook();
  const extension = path.extname(file).toLowerCase();
  if (extension === '.xlsx') await workbook.xlsx.readFile(file);
  else if (extension === '.csv') await workbook.csv.readFile(file);
  else throw new Error('Use an .xlsx or .csv file. Save older .xls files as .xlsx first.');
  const sheet = sheetName ? workbook.getWorksheet(sheetName) : workbook.worksheets[0];
  if (!sheet) throw new Error(`Worksheet ${sheetName ?? '(first sheet)'} not found.`);
  return parseWorksheet(sheet);
}
