import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:vehicle_poster/auction_vehicle.dart';
import 'package:vehicle_poster/poster_history.dart';
import 'package:vehicle_poster/poster.dart';
import 'package:xml/xml.dart';
import 'package:vehicle_poster/vehicles_label_screen.dart';

void main() {
  testWidgets('exports every label with unique names in one ZIP', (
    tester,
  ) async {
    final database = (await tester.runAsync(
      () => databaseFactoryMemory.openDatabase('labels-export'),
    ))!;
    addTearDown(database.close);
    final history = PosterHistory(openDatabase: () async => database);
    await tester.runAsync(() async {
      for (final number in ['10', '2']) {
        await history.save(
          VehicleDetails(
            number: number,
            title: 'TOYOTA 2013',
            model: 'CROLLA LE',
            color: 'Silver',
            vin: 'VIN-$number',
          ),
          [null, null, null, null],
        );
      }
      for (final vin in ['VIN-A', 'VIN-B']) {
        await history.createAuctionVehicle(
          AuctionVehicle(number: '7', vin: vin, vehicleType: 'Prius'),
        );
      }
    });
    final directory = Directory.systemTemp.createTempSync('labels-test-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final output = File('${directory.path}/labels.zip');
    var dialogs = 0;
    const channel = MethodChannel('plugins.flutter.io/file_selector');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      expect(call.method, 'getSavePath');
      expect(call.arguments['suggestedName'], 'vehicle_labels.zip');
      dialogs++;
      return output.path;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: VehiclesLabelScreen(history: history)),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.text('No. 2  ·  کرولا LE'), findsOneWidget);
    expect(find.textContaining('TOYOTA'), findsNothing);
    await tester.tap(find.text('No.: low to high'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No.: high to low').last);
    await tester.pumpAndSettle();
    final headings = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data ?? '')
        .where((text) => text.startsWith('No. '))
        .toList();
    expect(headings.first, 'No. 10  ·  کرولا LE');
    await tester.runAsync(() async {
      await tester.tap(find.text('Export all labels (ZIP)'));
      for (var attempt = 0; attempt < 100 && !output.existsSync(); attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(dialogs, 1);
    final archive = ZipDecoder().decodeBytes(output.readAsBytesSync());
    expect(archive.files, hasLength(4));
    expect(archive.files.map((file) => file.name).toSet(), hasLength(4));
    final contents = archive.files
        .map((file) => utf8.decode(file.content))
        .join();
    final firstLabel = XmlDocument.parse(
      utf8.decode(archive.files.first.content),
    );
    String field(String id) => firstLabel
        .findAllElements('text')
        .firstWhere((element) => element.getAttribute('id') == id)
        .innerText;
    expect(field('field-title'), 'کرولا LE');
    expect(field('field-year'), '2013');
    expect(field('field-color'), 'نقره‌ای');
    expect(field('main-number'), '10');
    expect(contents, isNot(contains('TOYOTA')));
    expect(contents, contains('VIN-A'));
    expect(contents, contains('VIN-B'));
    expect(contents, contains('پرویوس'));
    final saved = await tester.runAsync(history.list);
    expect(saved!.first.vehicle.title, 'TOYOTA 2013');
    expect(saved.first.vehicle.model, 'CROLLA LE');
    expect(saved.first.vehicle.color, 'Silver');
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Export all labels (ZIP)'),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing a label preserves raw poster model, color and brand', (
    tester,
  ) async {
    final database = (await tester.runAsync(
      () => databaseFactoryMemory.openDatabase('labels-edit'),
    ))!;
    addTearDown(database.close);
    final history = PosterHistory(openDatabase: () async => database);
    final id = (await tester.runAsync(
      () => history.save(
        const VehicleDetails(
          number: '2',
          title: 'TOYOTA 2013',
          model: 'CROLLA LE',
          color: 'Silver',
        ),
        [null, null, null, null],
      ),
    ))!;
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: VehiclesLabelScreen(history: history)),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.text('Edit')));
    await tester.pumpAndSettle();
    expect(find.text('CROLLA LE'), findsOneWidget);
    expect(find.text('Silver'), findsOneWidget);
    final yearField = find.widgetWithText(TextField, 'Year / Model');
    await tester.enterText(yearField, '2014');
    await tester.runAsync(() async {
      await tester.tap(find.text('Save changes'));
    });
    // The dialog closes on the frame clock; Sembast finishes on the real loop.
    for (var attempt = 0; attempt < 10; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pumpAndSettle();
    final draft = (await tester.runAsync(() => history.load(id)))!;
    expect(draft.vehicle.title, 'TOYOTA 2014');
    expect(draft.vehicle.model, 'CROLLA LE');
    expect(draft.vehicle.color, 'Silver');
    expect(find.text('No. 2  ·  کرولا LE'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
