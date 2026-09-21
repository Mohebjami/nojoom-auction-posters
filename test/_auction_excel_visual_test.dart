import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_poster/auction_excel_export.dart';
import 'package:vehicle_poster/auction_vehicle.dart';

void main() {
  test('writes a representative auction workbook for visual verification', () {
    final entries = [
      AuctionVehicleEntry(
        id: 1,
        vehicle: const AuctionVehicle(
          number: '1',
          vin: 'JTDKN3DU0A0231040',
          vehicleType: 'Prius',
          year: '2010',
          mileage: '125000',
          color: 'White',
          owner: 'Outside',
          redLight: '6500',
          greenLight: '7000',
          priceUsd: '6400',
        ),
        createdAt: DateTime.utc(2026, 9, 20),
        updatedAt: DateTime.utc(2026, 9, 20),
      ),
      AuctionVehicleEntry(
        id: 2,
        vehicle: const AuctionVehicle(
          number: '2',
          vin: 'JTEBU5JR3E5152433',
          vehicleType: '4Runner Limited',
          year: '2014',
          mileage: '183500',
          color: 'White',
          owner: 'Farhan Shakib',
          redLight: '23100',
          greenLight: '25000',
          priceUsd: '23000',
        ),
        createdAt: DateTime.utc(2026, 9, 20),
        updatedAt: DateTime.utc(2026, 9, 20),
      ),
    ];
    File('/private/tmp/auction-export-verify.xlsx').writeAsBytesSync(
      AuctionExcelExporter.export(entries, date: DateTime.utc(2026, 9, 20)),
    );
  });
}
