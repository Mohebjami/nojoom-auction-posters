import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart' hide Finder;
import 'package:vehicle_poster/auction_vehicle.dart';
import 'package:vehicle_poster/auction_vehicles_screen.dart';
import 'package:vehicle_poster/main.dart';
import 'package:vehicle_poster/poster.dart';
import 'package:vehicle_poster/poster_history.dart';
import 'package:vehicle_poster/vehicles_label_screen.dart';

class _FailingHistory extends PosterHistory {
  _FailingHistory(Database db) : super(openDatabase: () async => db);
  bool failSave = false;

  @override
  Future<int> save(
    VehicleDetails vehicle,
    List<Uint8List?> photos, {
    int? id,
    String? templateSvg,
    String? templateName,
    String? section,
  }) {
    if (failSave) throw StateError('Disk full');
    return super.save(
      vehicle,
      photos,
      id: id,
      templateSvg: templateSvg,
      templateName: templateName,
      section: section,
    );
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.runAsync(() => tester.tap(finder));
  await _settle(tester);
}

void main() {
  void useLargeView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  for (final failFirst in [false, true]) {
    testWidgets('poster save advances in number order, failure=$failFirst', (
      tester,
    ) async {
      useLargeView(tester);
      final db = (await tester.runAsync(
        () => databaseFactoryMemory.openDatabase('save-next-poster-$failFirst'),
      ))!;
      addTearDown(db.close);
      final history = _FailingHistory(db);
      final ids = <String, int>{};
      await tester.runAsync(() async {
        for (final number in ['10', '1', '2']) {
          ids[number] = await history.save(
            VehicleDetails(number: number, title: 'Vehicle $number'),
            [null, null, null, null],
          );
        }
      });
      await tester.pumpWidget(
        MaterialApp(home: EditorScreen(history: history)),
      );
      await _tap(tester, find.byTooltip('History'));
      final date = DateTime.now().toLocal();
      final dateKey =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';
      await _tap(tester, find.byKey(ValueKey('date-folder-$dateKey')));
      await _tap(tester, find.text('Vehicle 1').last);
      TextEditingController controller(String label) => tester
          .widget<TextField>(find.widgetWithText(TextField, label))
          .controller!;
      expect(controller('Top-left number').text, '1');
      controller('Top-left number').text = '99';
      controller('Price').text = '7000';
      if (failFirst) {
        history.failSave = true;
        await _tap(tester, find.text('Save changes'));
        expect(controller('Top-left number').text, '99');
        expect(controller('Price').text, '7000');
        expect(
          (await tester.runAsync(
            () => history.load(ids['1']!),
          ))!.vehicle.number,
          '1',
        );
        history.failSave = false;
      }
      await _tap(tester, find.text('Save changes'));
      expect(controller('Top-left number').text, '2');
      expect(controller('Price').text, isEmpty);
      final first = (await tester.runAsync(() => history.load(ids['1']!)))!;
      expect(first.vehicle.number, '99');
      expect(first.vehicle.price, '7000');
      await _tap(tester, find.text('Save changes'));
      expect(controller('Top-left number').text, '10');
      await _tap(tester, find.text('Save changes'));
      expect(controller('Top-left number').text, '10');
      expect((await tester.runAsync(history.list))!, hasLength(3));
      await _tap(tester, find.byTooltip('New poster'));
      controller('Top-left number').text = '3';
      await _tap(tester, find.text('Save draft'));
      expect(controller('Top-left number').text, '3');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('auction Save opens 2 then 10 and closes at the end', (
    tester,
  ) async {
    useLargeView(tester);
    final db = (await tester.runAsync(
      () => databaseFactoryMemory.openDatabase('save-next-auction'),
    ))!;
    addTearDown(db.close);
    final history = PosterHistory(openDatabase: () async => db);
    await tester.runAsync(() async {
      for (final number in ['10', '1', '2']) {
        await history.createAuctionVehicle(
          AuctionVehicle(
            number: number,
            vin: 'JTDKN3DU0A0231040',
            vehicleType: 'Car $number',
            year: '2010',
            color: 'White',
            owner: 'Outside',
          ),
        );
      }
    });
    await tester.pumpWidget(
      MaterialApp(home: AuctionVehiclesScreen(history: history)),
    );
    await _settle(tester);
    await _tap(tester, find.byTooltip('Edit vehicle 1'));
    String number() => tester
        .widget<TextFormField>(find.byType(TextFormField).first)
        .controller!
        .text;
    expect(number(), '1');
    await tester.enterText(find.byType(TextFormField).first, '99');
    await _tap(tester, find.text('Save changes'));
    expect(number(), '2');
    await _tap(tester, find.text('Save changes'));
    expect(number(), '10');
    await _tap(tester, find.text('Save changes'));
    expect(find.text('Edit auction vehicle'), findsNothing);
    final entries = (await tester.runAsync(history.listAuctionVehicles))!;
    expect(entries.map((entry) => entry.vehicle.number), contains('99'));
    expect(entries, hasLength(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('label Save advances across posters and auction vehicles', (
    tester,
  ) async {
    useLargeView(tester);
    final db = (await tester.runAsync(
      () => databaseFactoryMemory.openDatabase('save-next-label'),
    ))!;
    addTearDown(db.close);
    final history = PosterHistory(openDatabase: () async => db);
    final ids = <String, int>{};
    await tester.runAsync(() async {
      for (final number in ['10', '1']) {
        ids[number] = await history.save(
          VehicleDetails(
            number: number,
            title: 'TOYOTA 2010',
            model: 'Car $number',
          ),
          [null, null, null, null],
        );
      }
      await history.createAuctionVehicle(
        const AuctionVehicle(number: '2', vehicleType: 'Car 2'),
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: VehiclesLabelScreen(history: history)),
      ),
    );
    await _settle(tester);
    await _tap(tester, find.text('Edit').first);
    final numberField = find.widgetWithText(TextField, 'No.');
    String number() => tester.widget<TextField>(numberField).controller!.text;
    expect(number(), '1');
    await tester.enterText(numberField, '99');
    await tester.enterText(find.widgetWithText(TextField, 'Price'), '7000');
    await _tap(tester, find.text('Save changes'));
    expect(find.text('Edit vehicle label'), findsOneWidget);
    expect(number(), '2');
    await tester.enterText(find.widgetWithText(TextField, 'Price'), '8000');
    await _tap(tester, find.text('Save changes'));
    expect(number(), '10');
    await _tap(tester, find.text('Save changes'));
    expect(find.text('Edit vehicle label'), findsNothing);
    final first = (await tester.runAsync(() => history.load(ids['1']!)))!;
    expect(first.vehicle.number, '99');
    expect(first.vehicle.price, '7000');
    expect(
      (await tester.runAsync(
        history.listAuctionVehicles,
      ))!.single.vehicle.priceUsd,
      '8000',
    );
    expect(tester.takeException(), isNull);
  });
}
