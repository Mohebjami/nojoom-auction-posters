import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:vehicle_poster/auction_excel_export.dart';
import 'package:vehicle_poster/auction_vehicle.dart';
import 'package:vehicle_poster/main.dart';
import 'package:vehicle_poster/poster.dart';
import 'package:vehicle_poster/poster_history.dart';

Future<void> _settleStorage(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  // The editor's busy spinner stays animated behind the duplicate dialog.
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  for (final action in ['Replace', 'Skip', 'Cancel import']) {
    testWidgets('Excel import handles $action before saving any rows', (
      tester,
    ) async {
      final db = (await tester.runAsync(
        () => databaseFactoryMemory.openDatabase('xlsx-import-$action'),
      ))!;
      addTearDown(db.close);
      final history = PosterHistory(openDatabase: () async => db);
      final id = (await tester.runAsync(
        () => history.save(
          const VehicleDetails(number: '1', vin: 'ABC', price: '6000'),
          [null, null, null, null],
          templateSvg: '<svg/>',
          templateName: 'Saved template',
        ),
      ))!;
      final directory = Directory.systemTemp.createTempSync('xlsx-duplicates-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/vehicles.xlsx');
      file.writeAsBytesSync(
        AuctionExcelExporter.export([
          for (final (index, vehicle) in const [
            AuctionVehicle(number: '2', vin: 'NEW', vehicleType: 'New car'),
            AuctionVehicle(number: '1', vin: 'abc', priceUsd: '7000'),
            AuctionVehicle(number: '1', vin: 'ABC', priceUsd: '8000'),
          ].indexed)
            AuctionVehicleEntry(
              id: index,
              vehicle: vehicle,
              createdAt: DateTime.utc(2026, 10, 4),
              updatedAt: DateTime.utc(2026, 10, 4),
            ),
        ]),
      );
      const channel = MethodChannel('plugins.flutter.io/file_selector');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        expect(call.method, 'openFile');
        return [file.path];
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      var openedHistory = false;
      await tester.pumpWidget(
        MaterialApp(
          home: EditorScreen(
            history: history,
            onShowHistory: () => openedHistory = true,
          ),
        ),
      );
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Import spreadsheet'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await _settleStorage(tester);
      expect(find.text('Duplicate vehicle found'), findsOneWidget);
      expect((await tester.runAsync(history.list))!, hasLength(1));
      if (action != 'Cancel import') {
        await tester.ensureVisible(find.byType(CheckboxListTile));
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pump();
      }
      await tester.runAsync(() async {
        await tester.tap(find.text(action));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await _settleStorage(tester);
      expect(find.text('Duplicate vehicle found'), findsNothing);
      final entries = (await tester.runAsync(history.list))!;
      final saved = (await tester.runAsync(() => history.load(id)))!;
      expect(entries, hasLength(action == 'Cancel import' ? 1 : 2));
      expect(saved.vehicle.price, action == 'Replace' ? '8000' : '6000');
      expect(saved.templateName, 'Saved template');
      expect(openedHistory, action != 'Cancel import');
      expect(tester.takeException(), isNull);
    });
  }
}
