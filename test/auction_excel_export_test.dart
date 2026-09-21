import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_poster/auction_excel_export.dart';
import 'package:vehicle_poster/auction_vehicle.dart';
import 'package:xml/xml.dart';

AuctionVehicleEntry _entry(int id, AuctionVehicle vehicle) =>
    AuctionVehicleEntry(
      id: id,
      vehicle: vehicle,
      createdAt: DateTime.utc(2026, 9, 20),
      updatedAt: DateTime.utc(2026, 9, 20),
    );

String _archiveText(Archive archive, String path) {
  final file = archive.findFile(path);
  expect(file, isNotNull, reason: 'Missing $path in the XLSX archive.');
  return utf8.decode(file!.readBytes()!);
}

void main() {
  test('Auction export creates a styled XLSX in the supplied list layout', () {
    final bytes = AuctionExcelExporter.export([
      _entry(
        2,
        const AuctionVehicle(
          number: '10',
          vin: 'JTEBU5JR3E5152433',
          vehicleType: '4Runner Limited',
          year: '2014',
          mileage: '183500',
          color: 'White',
          owner: 'Outside & Partners',
          redLight: '23100',
          greenLight: '25000',
          priceUsd: '23000',
        ),
      ),
      _entry(
        1,
        const AuctionVehicle(
          number: '2',
          vin: 'JTDKN3DU0A0231040',
          vehicleType: 'Prius',
          year: '2010',
          // Mileage and all price fields may be omitted from an auction row.
          mileage: '',
          color: 'White',
          owner: 'Outside',
        ),
      ),
    ], date: DateTime.utc(2026, 9, 20));

    expect(bytes.take(2), [0x50, 0x4b]);
    final archive = ZipDecoder().decodeBytes(bytes);
    expect(archive.findFile('[Content_Types].xml'), isNotNull);
    expect(archive.findFile('xl/workbook.xml'), isNotNull);
    expect(archive.findFile('xl/styles.xml'), isNotNull);
    expect(archive.findFile('xl/worksheets/sheet1.xml'), isNotNull);
    expect(archive.findFile('xl/worksheets/sheet2.xml'), isNotNull);

    final workbook = _archiveText(archive, 'xl/workbook.xml');
    expect(workbook, contains('name="Sheet1"'));
    expect(workbook, contains('name="Sounce" sheetId="2" state="hidden"'));
    expect(workbook, contains('Sheet1!\$A\$1:\$L\$5'));

    final sheet = _archiveText(archive, 'xl/worksheets/sheet1.xml');
    final sheetDocument = XmlDocument.parse(sheet);
    expect(
      sheetDocument
          .findAllElements('mergeCell')
          .map((cell) => cell.getAttribute('ref')),
      containsAll(['A1:L1', 'A2:B2']),
    );
    expect(sheet, contains('Auction List'));
    expect(sheet, contains('Date: 9/20/2026'));
    expect(sheet, contains('No.'));
    expect(sheet, contains('Vehicle Type'));
    expect(sheet, contains('Mileage'));
    expect(sheet, contains('Red Light'));
    expect(sheet, contains('Green Light'));
    expect(sheet, contains('Price (USD)'));
    expect(sheet, contains('Auction Price\n(Sold)'));
    expect(sheet, contains('Outside &amp; Partners'));

    // Rows are exported in No. order. Blank optional values remain blank,
    // while populated mileage and money values remain numeric for Excel.
    expect(sheet.indexOf('<c r="A4"'), lessThan(sheet.indexOf('<c r="A5"')));
    expect(sheet, contains('<c r="A4" s="13"><v>2</v></c>'));
    expect(sheet, contains('<c r="E4" s="14"/>'));
    expect(sheet, contains('<c r="H4" s="15"/>'));
    expect(sheet, contains('<c r="I4" s="15"/>'));
    expect(sheet, contains('<c r="J4" s="15"/>'));
    expect(sheet, contains('<c r="A5" s="25"><v>10</v></c>'));
    expect(sheet, contains('<c r="E5" s="26"><v>183500</v></c>'));
    expect(sheet, contains('<c r="J5" s="27"><v>23000</v></c>'));

    final styles = _archiveText(archive, 'xl/styles.xml');
    XmlDocument.parse(styles);
    expect(styles, contains('FF4BACC6'));
    expect(styles, contains('FFFF0000'));
    expect(styles, contains('FF00B050'));
    expect(styles, contains('formatCode="&quot;\$&quot;#,##0"'));
  });
}
