import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:vehicle_poster/history_screen.dart';
import 'package:vehicle_poster/main.dart';
import 'package:vehicle_poster/poster.dart';
import 'package:vehicle_poster/poster_history.dart';
import 'package:vehicle_poster/studio_ui.dart';

import 'history_test.dart' show settleStorage;

Future<void> screenshot(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory('build/verification').createSync(recursive: true);
    File(
      'build/verification/$name.png',
    ).writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  late Uint8List photo;
  setUpAll(() async {
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final font = File('/System/Library/Fonts/Supplemental/Arial.ttf');
    if (font.existsSync()) {
      await (FontLoader('Roboto')..addFont(
            Future.value(ByteData.sublistView(font.readAsBytesSync())),
          ))
          .load();
    }
    final svg = File('reference/Group 11.svg').readAsStringSync();
    final start = svg.indexOf('<image id="image0_2231_392"');
    final href = svg.indexOf('xlink:href="', start) + 'xlink:href="'.length;
    final uri = svg.substring(href, svg.indexOf('"', href));
    photo = base64Decode(uri.substring(uri.indexOf(',') + 1));
  });

  for (final size in [const Size(390, 844), const Size(1440, 1000)]) {
    testWidgets('History search, filter, views and deletion at ${size.width}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = (await tester.runAsync(
        () => databaseFactoryMemory.openDatabase('studio-${size.width}'),
      ))!;
      addTearDown(db.close);
      final history = PosterHistory(openDatabase: () async => db);
      await tester.runAsync(() async {
        final oldId = await history.save(
          const VehicleDetails(
            title: '2020 HONDA',
            model: 'CIVIC',
            number: '12',
            price: '18500',
          ),
          [null, null, null, null],
        );
        await intMapStoreFactory.store('entries').record(oldId).update(db, {
          'updatedAt': DateTime.now()
              .subtract(const Duration(days: 15))
              .toUtc()
              .toIso8601String(),
        });
        await history.save(
          const VehicleDetails(
            title: '2010 TOYOTA',
            model: 'COROLLA',
            number: '09',
            price: '6000',
            vin: 'TESTVIN123',
          ),
          [photo, null, null, null],
        );
      });
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: studioTheme(),
          home: RepaintBoundary(
            key: key,
            child: HistoryScreen(history: history),
          ),
        ),
      );
      await settleStorage(tester);
      // The visible cards start loading thumbnails after the entry list resolves.
      await settleStorage(tester);
      expect(find.byType(Image), findsOneWidget);
      await tester.runAsync(() async {
        for (final widget in tester.widgetList<Image>(find.byType(Image))) {
          await precacheImage(widget.image, key.currentContext!);
        }
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await screenshot(tester, key, 'history-${size.width.toInt()}');

      await tester.tap(find.text('This week'));
      await settleStorage(tester);
      expect(find.text('2020 HONDA CIVIC'), findsNothing);
      expect(find.text('2010 TOYOTA COROLLA'), findsOneWidget);
      await tester.tap(find.text('All posters'));
      await tester.tap(find.byTooltip('List view'));
      await tester.pumpAndSettle();
      expect(find.byType(SliverGrid), findsNothing);
      await tester.tap(find.text('Newest first'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Oldest first').last);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('2020 HONDA CIVIC')).dy,
        lessThan(tester.getTopLeft(find.text('2010 TOYOTA COROLLA')).dy),
      );
      await tester.enterText(find.byType(TextField), 'TESTVIN123');
      await tester.pumpAndSettle();
      expect(find.text('2020 HONDA CIVIC'), findsNothing);
      expect(find.text('2010 TOYOTA COROLLA'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'missing vehicle');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('No matching posters'));
      expect(find.text('No matching posters'), findsOneWidget);
      await tester.ensureVisible(find.text('Clear filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Delete 2020 HONDA CIVIC'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete 2020 HONDA CIVIC'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await tester.runAsync(history.list), hasLength(2));
      await tester.tap(find.byTooltip('Delete 2020 HONDA CIVIC'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      // Drain the dialog result and database transaction before settling animations.
      await tester.pump();
      await tester.runAsync(history.list);
      for (var turn = 0; turn < 5; turn++) {
        await tester.runAsync(() async {
          await tester.pump(const Duration(milliseconds: 300));
          await Future<void>.delayed(const Duration(milliseconds: 30));
        });
      }
      await tester.pumpAndSettle();
      expect(await tester.runAsync(history.list), hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Empty history and unavailable storage provide recovery actions',
    (tester) async {
      final db = (await tester.runAsync(
        () => databaseFactoryMemory.openDatabase('empty-ui'),
      ))!;
      addTearDown(db.close);
      var fail = true;
      final history = PosterHistory(
        openDatabase: () async {
          if (fail) throw const FileSystemException('Unavailable');
          return db;
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: studioTheme(),
          home: HistoryScreen(history: history),
        ),
      );
      await settleStorage(tester);
      expect(find.text('Retry'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Retry'));
      await settleStorage(tester);
      expect(find.text('Your next great poster starts here.'), findsOneWidget);
      expect(find.text('Go to editor'), findsOneWidget);
    },
  );

  testWidgets('Small phone with keyboard keeps editor actions accessible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const VehiclePosterApp());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Generate poster').hitTestable(), findsOneWidget);
    await tester.ensureVisible(find.byType(TextField).first);
    await tester.tap(find.byType(TextField).first);
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetViewInsets);
    await tester.enterText(find.byType(TextField).first, 'Toyota');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Generate poster').hitTestable(), findsOneWidget);
  });
}
