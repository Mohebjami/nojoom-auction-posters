import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sembast/sembast_io.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:vehicle_poster/main.dart';
import 'package:vehicle_poster/poster.dart';
import 'package:vehicle_poster/poster_export.dart';
import 'package:vehicle_poster/poster_history.dart';
import 'package:vehicle_poster/vehicle_import.dart';

Future<void> settleStorage(WidgetTester tester) async {
  // Sembast's streams run on the real event loop, outside the fake frame clock.
  await tester.runAsync(() async {
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 30));
  });
  await tester.pumpAndSettle();
}

void main() {
  const vehicle = VehicleDetails(
    number: '009',
    title: 'Toyota',
    model: 'Corolla',
    price: '6000.50',
    color: 'Silver',
    vin: 'JTDKN3DU2A0090987',
  );

  test(
    'History survives closing storage and preserves original photos and raw fields',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'poster-history-test-',
      );
      final path = '${directory.path}/history.db';
      var db = await databaseFactoryIo.openDatabase(path);
      addTearDown(() async {
        await db.close();
        await directory.delete(recursive: true);
      });
      var history = PosterHistory(openDatabase: () async => db);
      final photos = [
        Uint8List.fromList([1, 2, 3]),
        null,
        Uint8List.fromList([4, 5]),
        null,
      ];
      final id = await history.save(vehicle, photos);
      final first = await history.load(id);
      await db.close();
      db = await databaseFactoryIo.openDatabase(path);
      history = PosterHistory(openDatabase: () async => db);
      final restored = await history.load(id);
      expect(restored.vehicle.toJson(), vehicle.toJson());
      expect(restored.photos, photos);
      expect(restored.createdAt, first.createdAt);

      const edited = VehicleDetails(price: '7000');
      final updatedId = await history.save(edited, [
        null,
        photos[0],
        null,
        null,
      ], id: id);
      expect(updatedId, id);
      expect(await history.list(), hasLength(1));
      final updated = await history.load(id);
      expect(updated.createdAt, first.createdAt);
      expect(updated.vehicle.price, '7000');
      expect(updated.photos, [null, photos[0], null, null]);

      final newId = await history.save(vehicle, photos);
      expect(newId, isNot(id));
      expect((await history.list()).first.id, newId);
      await history.delete(id);
      expect((await history.list()).single.id, newId);
      await expectLater(history.load(id), throwsStateError);
      await expectLater(history.save(edited, photos, id: id), throwsStateError);
    },
  );

  test('Storage can retry after opening fails', () async {
    final db = await databaseFactoryMemory.openDatabase('retry');
    addTearDown(db.close);
    var attempts = 0;
    final history = PosterHistory(
      openDatabase: () async {
        if (attempts++ == 0) {
          throw const FileSystemException('Storage unavailable');
        }
        return db;
      },
    );
    await expectLater(history.list(), throwsA(isA<FileSystemException>()));
    expect(await history.list(), isEmpty);
  });

  test(
    'Spreadsheet rows import as saved drafts with the expected fields',
    () async {
      const csv = '''
Number,Vehicle,Year,Color,Price (USD),Stock / ID
2,2010 TOYOTA COROLLA,2010,SILVER,6000,JTDKN3DU2A0090987
5,2018 HONDA CIVIC,2018,BLACK,18500,5YFGA4A36J
''';

      final rows = await VehicleListImporter.fromBytes(
        'sample.csv',
        utf8.encode(csv),
      );

      expect(rows, hasLength(2));
      expect(rows[0].number, '2');
      expect(rows[0].title, '2010 TOYOTA COROLLA');
      expect(rows[0].model, '2010');
      expect(rows[0].color, 'SILVER');
      expect(rows[0].price, '6000');
      expect(rows[0].vin, 'JTDKN3DU2A0090987');
      expect(rows[1].title, '2018 HONDA CIVIC');
    },
  );

  test(
    'JPG has valid JPEG bytes, original size, and white transparent areas',
    () {
      final source = img.Image(width: 32, height: 24, numChannels: 4);
      img.fillRect(
        source,
        x1: 16,
        y1: 0,
        x2: 31,
        y2: 23,
        color: img.ColorRgba8(255, 0, 0, 255),
      );
      final jpg = encodePosterJpg(img.encodePng(source));
      expect(jpg.take(3), [0xff, 0xd8, 0xff]);
      final decoded = img.decodeJpg(jpg)!;
      expect(decoded.width, 32);
      expect(decoded.height, 24);
      final white = decoded.getPixel(3, 3);
      expect(white.r, greaterThan(245));
      expect(white.g, greaterThan(245));
      expect(white.b, greaterThan(245));
      final red = decoded.getPixel(27, 3);
      expect(red.r, greaterThan(240));
      expect(red.g, lessThan(15));
      expect(red.b, lessThan(15));
    },
  );

  testWidgets(
    'History reopens all fields and photos and saves edits to the same entry',
    (tester) async {
      final db = (await tester.runAsync(
        () => databaseFactoryMemory.openDatabase('editor-history'),
      ))!;
      addTearDown(db.close);
      final history = PosterHistory(openDatabase: () async => db);
      final photo = img.encodePng(img.Image(width: 20, height: 20));
      final id = (await tester.runAsync(
        () => history.save(vehicle, [photo, null, photo, null]),
      ))!;
      await tester.pumpWidget(
        MaterialApp(home: EditorScreen(history: history)),
      );
      await tester.tap(find.byTooltip('History'));
      await settleStorage(tester);
      await tester.ensureVisible(find.text('Toyota Corolla'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Toyota Corolla'));
      await settleStorage(tester);
      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList();
      expect(fields.map((field) => field.controller!.text), [
        vehicle.title,
        vehicle.model,
        vehicle.price,
        vehicle.color,
        vehicle.vin,
        vehicle.number,
      ]);
      expect(find.byType(Image), findsNWidgets(2));
      fields[2].controller!.text = '7500';
      await tester.tap(find.text('Save changes'));
      await settleStorage(tester);
      expect(
        (await tester.runAsync(() => history.load(id)))!.vehicle.price,
        '7500',
      );
      expect(await tester.runAsync(history.list), hasLength(1));
      await tester.tap(find.byTooltip('New poster'));
      await tester.pumpAndSettle();
      expect(fields.every((field) => field.controller!.text.isEmpty), isTrue);
      expect(find.byType(Image), findsNothing);
      expect(find.text('Save draft'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Unsaved changes can be kept when starting a new poster', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: EditorScreen()));
    final field = tester.widget<TextField>(find.byType(TextField).first);
    field.controller!.text = 'Keep this';
    await tester.tap(find.byTooltip('New poster'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(field.controller!.text, 'Keep this');
  });

  testWidgets('A failed draft save keeps the editor values and offers retry', (
    tester,
  ) async {
    final history = PosterHistory(
      openDatabase: () async => throw const FileSystemException('Disk full'),
    );
    await tester.pumpWidget(MaterialApp(home: EditorScreen(history: history)));
    final field = tester.widget<TextField>(find.byType(TextField).first);
    field.controller!.text = 'My poster';
    await tester.tap(find.text('Save draft'));
    await tester.pumpAndSettle();
    expect(field.controller!.text, 'My poster');
    expect(find.textContaining('Could not save poster'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Save draft'))
          .onPressed,
      isNotNull,
    );
  });
}
