function toCSV(rows) {
  // Quote cells and prevent imported text from being interpreted as a formula.
  const quote = value => `"${String(value ?? '').replace(/^[=+@\-\t\r]/, "'$&").replace(/"/g, '""')}"`;
  return '\ufeff' + rows.map(row => row.map(quote).join(',')).join('\r\n');
}

function notFoundReport(vehicles) {
  const rows = vehicles.filter(vehicle => vehicle.status === 'not_found');
  return {
    count: rows.length,
    csv: toCSV([['No.', 'VIN', 'Vehicle', 'Year'], ...rows.map(v => [v.no, v.vin, v.vehicle, v.year])]),
  };
}

module.exports = { toCSV, notFoundReport };
