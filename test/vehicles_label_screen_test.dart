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
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:printing/src/interface.dart';
import 'package:vehicle_poster/vehicles_label_screen.dart';

class _TestPrinting extends PrintingPlatform {
  final jobs = <String>[];
  final pageCounts = <int>[];
  bool fail = false;

  @override
  Future<bool> layoutPdf(
    Printer? printer,
    LayoutCallback onLayout,
    String name,
    PdfPageFormat format,
    bool dynamicLayout,
    bool usePrinterSettings,
    OutputType outputType,
    bool forceCustomPrintPaper,
    bool windowsModernDialog,
  ) async {
    if (fail) throw StateError('Printer unavailable');
    jobs.add(name);
    final pdf = latin1.decode(await onLayout(PdfPageFormat.a4));
    pageCounts.add(RegExp(r'/Type\s*/Page\b').allMatches(pdf).length);
    return false; // A cancelled dialog must also restore the controls.
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'search scopes labels and printing, with cancellation and errors',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final database = (await tester.runAsync(
        () => databaseFactoryMemory.openDatabase('label-search-print'),
      ))!;
      addTearDown(database.close);
      final history = PosterHistory(openDatabase: () async => database);
      await tester.runAsync(() async {
        await history.createAuctionVehicle(
          const AuctionVehicle(
            number: '2',
            vehicleType: 'Corolla',
            year: '2013',
            color: 'Silver',
            vin: 'VIN-COROLLA',
            priceUsd: '6500',
          ),
        );
        final id = await history.createAuctionVehicle(
          const AuctionVehicle(
            number: '10',
            vehicleType: 'Prius',
            year: '2017',
            color: 'Black',
            vin: 'VIN-PRIUS',
          ),
        );
        await intMapStoreFactory.store('auction_vehicles').record(id).update(
          database,
          {'createdAt': DateTime(2025, 1, 3).toUtc().toIso8601String()},
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: VehiclesLabelScreen(history: history)),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      final previous = PrintingPlatform.instance;
      final printing = _TestPrinting();
      PrintingPlatform.instance = printing;
      addTearDown(() => PrintingPlatform.instance = previous);
      Future<void> printButton(String label) async {
        await tester.runAsync(() async {
          await tester.tap(find.text(label).first);
          for (var attempt = 0; attempt < 300; attempt++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            // Printing finishes off the widget test's simulated clock.
            if (printing.jobs.isNotEmpty &&
                printing.pageCounts.length == printing.jobs.length) {
              break;
            }
          }
        });
        await tester.pumpAndSettle();
      }

      await printButton('Print all labels');
      expect(printing.pageCounts, [2]);
      printing.jobs.clear();
      printing.pageCounts.clear();
      await printButton('Print');
      expect(printing.jobs, ['Vehicle label 2']);
      expect(printing.pageCounts, [1]);
      final search = find.byKey(const ValueKey('label-search'));
      for (final query in [
        'COROLLA',
        'vin-corolla',
        '2013',
        'silver',
        'نقره‌ای',
        'کرولا',
        '6500',
        '2 2013',
      ]) {
        await tester.enterText(search, query);
        await tester.pumpAndSettle();
        expect(find.text('No. 2  ·  کرولا'), findsOneWidget);
        expect(find.text('No. 10  ·  پریوس'), findsNothing);
      }
      printing.jobs.clear();
      printing.pageCounts.clear();
      await printButton('Print matching labels (1)');
      expect(printing.pageCounts, [1]);
      await tester.enterText(search, 'missing');
      await tester.pumpAndSettle();
      expect(find.text('No labels match your search.'), findsOneWidget);
      expect(find.text('Print all labels'), findsNothing);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('label-folder-2025-01-03')));
      await tester.pumpAndSettle();
      expect(find.text('No. 2  ·  کرولا'), findsNothing);
      printing.jobs.clear();
      printing.pageCounts.clear();
      await printButton('Print folder labels');
      expect(printing.jobs, ['Vehicle label 10']);
      expect(printing.pageCounts, [1]);
      printing.fail = true;
      await tester.runAsync(() async {
        await tester.tap(find.text('Print'));
        await Future<void>.delayed(const Duration(seconds: 2));
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not print labels:'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Print'),
            )
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'import date survives edits and is refreshed by a later import',
    () async {
      final database = await databaseFactoryMemory.openDatabase('label-dates');
      addTearDown(database.close);
      final history = PosterHistory(openDatabase: () async => database);
      const vehicle = VehicleDetails(number: '1', vin: 'VIN-1');
      await history.importVehicleDetails([(id: null, vehicle: vehicle)]);
      final original = (await history.list()).single;
      final createdAt = (await history.load(original.id)).createdAt;
      final store = intMapStoreFactory.store('entries');
      final oldDate = DateTime(2025, 1, 2).toUtc();
      await store.record(original.id).update(database, {
        'labelDate': oldDate.toIso8601String(),
      });
      await history.save(
        const VehicleDetails(number: '1', vin: 'VIN-1', price: '5000'),
        [null, null, null, null],
        id: original.id,
      );
      expect((await history.list()).single.labelDate, oldDate);
      await history.importVehicleDetails([(id: original.id, vehicle: vehicle)]);
      final reimported = (await history.list()).single;
      expect(reimported.labelDate, reimported.updatedAt);
      expect(reimported.labelDate.isAfter(oldDate), isTrue);
      expect((await history.load(original.id)).createdAt, createdAt);
    },
  );

  testWidgets('date folders filter export, edit queue and deletion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final database = (await tester.runAsync(
      () => databaseFactoryMemory.openDatabase('label-folders'),
    ))!;
    addTearDown(database.close);
    final history = PosterHistory(openDatabase: () async => database);
    await tester.runAsync(() async {
      final id = await history.save(
        const VehicleDetails(number: '1', vin: 'SAME-VIN', model: 'Corolla'),
        [null, null, null, null],
      );
      // Older records have no labelDate: use their creation date, not the edit date.
      final store = intMapStoreFactory.store('entries');
      final record = Map<String, Object?>.from(
        (await store.record(id).get(database))!,
      );
      record.remove('labelDate');
      record['createdAt'] = DateTime(2025, 1, 2).toUtc().toIso8601String();
      await store.record(id).put(database, record);
      final auctionId = await history.createAuctionVehicle(
        const AuctionVehicle(
          number: '1',
          vin: 'SAME-VIN',
          vehicleType: 'Prius',
        ),
      );
      await intMapStoreFactory
          .store('auction_vehicles')
          .record(auctionId)
          .update(database, {
            'createdAt': DateTime(2025, 1, 3).toUtc().toIso8601String(),
          });
    });
    final directory = Directory.systemTemp.createTempSync(
      'folder-labels-test-',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final output = File('${directory.path}/labels.zip');
    const channel = MethodChannel('plugins.flutter.io/file_selector');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      expect(call.arguments['suggestedName'], 'vehicle_labels_2025-01-02.zip');
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
    expect(find.text('2025-01-02 (1)'), findsOneWidget);
    expect(find.text('2025-01-03 (1)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('label-folder-2025-01-02')));
    await tester.pumpAndSettle();
    expect(find.text('No. 1  ·  کرولا'), findsOneWidget);
    expect(find.text('No. 1  ·  پریوس'), findsNothing);
    await tester.runAsync(() => tester.tap(find.text('Edit')));
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.text('Save changes')));
    for (var attempt = 0; attempt < 10; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pumpAndSettle();
    expect(find.text('Edit vehicle label'), findsNothing);
    expect(find.text('No. 1  ·  کرولا'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('Export folder labels (ZIP)'));
      for (var attempt = 0; attempt < 100 && !output.existsSync(); attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    final archive = ZipDecoder().decodeBytes(output.readAsBytesSync());
    expect(archive.files, hasLength(1));
    expect(utf8.decode(archive.files.single.content), contains('کرولا'));
    await tester.tap(find.text('Delete folder'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.text('Delete all')));
    for (var attempt = 0; attempt < 10; attempt++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pumpAndSettle();
    expect(await tester.runAsync(history.list), isEmpty);
    expect(await tester.runAsync(history.listAuctionVehicles), hasLength(1));
    expect(find.text('2025-01-02 (1)'), findsNothing);
    expect(find.text('No. 1  ·  پریوس'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('exports every label with unique names in one ZIP', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
          AuctionVehicle(
            number: '7',
            vin: vin,
            vehicleType: 'Prius 4Runner Lexus Land Cruiser',
          ),
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
    expect(find.text('No. 7  ·  پریوس فورنر لکسیز لندکروزر'), findsWidgets);
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
    expect(contents, contains('پریوس'));
    expect(contents, contains('فورنر'));
    expect(contents, contains('لکسیز'));
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
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
