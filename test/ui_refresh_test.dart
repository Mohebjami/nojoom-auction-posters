import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:vehicle_poster/auction_vehicle.dart';
import 'package:vehicle_poster/poster_history.dart';
import 'package:vehicle_poster/studio_ui.dart';
import 'package:vehicle_poster/vehicles_label_screen.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final font = File('/System/Library/Fonts/Supplemental/Arial.ttf');
    if (font.existsSync()) {
      await (FontLoader('Roboto')..addFont(
            Future.value(ByteData.sublistView(font.readAsBytesSync())),
          ))
          .load();
    }
  });
  for (final size in [const Size(390, 844), const Size(1440, 1000)]) {
    testWidgets('responsive labels and navigation at ${size.width}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final database = (await tester.runAsync(
        () => databaseFactoryMemory.openDatabase('ui-${size.width}'),
      ))!;
      addTearDown(database.close);
      final history = PosterHistory(openDatabase: () async => database);
      final key = GlobalKey();
      var navigated = false;
      await tester.runAsync(() async {
        for (final number in ['2', '7']) {
          await history.createAuctionVehicle(
            AuctionVehicle(
              number: number,
              vehicleType: 'COROLLA',
              year: '2020',
              vin: 'JTDBR32E720123456',
              priceUsd: '12,500',
              color: 'White',
            ),
          );
        }
        await tester.pumpWidget(
          MaterialApp(
            theme: studioTheme(),
            home: RepaintBoundary(
              key: key,
              child: StudioShell(
                section: 'Vehicles Label',
                onEditor: () => navigated = true,
                onHistory: () {},
                onAuctionVehicles: () {},
                onVehiclesLabel: () {},
                onNew: () {},
                child: VehiclesLabelScreen(history: history),
              ),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory('build/verification').createSync(recursive: true);
        File(
          'build/verification/ui-refresh-${size.width.toInt()}.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.tap(find.byKey(const ValueKey('studio-tab-create')));
      expect(navigated, isTrue);
    });
  }
}
