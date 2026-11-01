import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:vehicle_poster/automation/automation_client.dart';
import 'package:vehicle_poster/automation/automation_screens.dart';
import 'package:vehicle_poster/automation/photo_attachment.dart';
import 'package:vehicle_poster/main.dart';
import 'package:vehicle_poster/poster.dart';
import 'package:vehicle_poster/poster_history.dart';
import 'package:vehicle_poster/studio_ui.dart';

class FakeAutomation extends AutomationClient {
  final calls = <String>[];
  FakeAutomation() {
    state = {
      'photos': {
        'filename': 'auction.xlsx',
        'vehicles': [],
        'sourceMode': 'both',
        'running': false,
      },
      'importer': {
        'file': '/auction.xlsx',
        'filename': 'auction.xlsx',
        'running': false,
        'vehicles': [
          {
            'vin': 'JTDKN3DU0B1457686',
            'row': 2,
            'biddingStart': 1000,
            'greenLight': 1200,
          },
        ],
        'results': [],
      },
    };
  }
  @override
  bool get supported => true;
  @override
  Future<void> start() async {}
  @override
  Future<Map<String, dynamic>> invoke(
    String action, [
    Map<String, dynamic> args = const {},
  ]) async {
    calls.add(action);
    return state;
  }
}

void main() {
  test(
    'downloaded photos fill only empty slots for exact VIN and preserve saved metadata',
    () async {
      final db = await databaseFactoryMemory.openDatabase('photo-attachment');
      addTearDown(db.close);
      final history = PosterHistory(openDatabase: () async => db);
      final existing = Uint8List.fromList([1, 2]);
      final first = Uint8List.fromList([3, 4]);
      final second = Uint8List.fromList([5, 6]);
      final id = await history.save(
        const VehicleDetails(vin: ' jtdkn3du0b1457686 ', price: '3000'),
        [existing, null, null, existing],
        templateSvg: '<svg/>',
        templateName: 'Custom',
      );
      final other = await history.save(
        const VehicleDetails(vin: 'JTDKN3DU0B1457687'),
        [null, null, null, null],
      );
      final before = await history.load(id);
      expect(
        await attachDownloadedPhotos(history, 'JTDKN3DU0B1457686', [
          first,
          second,
        ]),
        1,
      );
      final after = await history.load(id);
      expect(after.photos, [existing, first, second, existing]);
      expect(after.createdAt, before.createdAt);
      expect(after.templateSvg, before.templateSvg);
      expect(after.templateName, before.templateName);
      expect(after.vehicle.price, '3000');
      expect((await history.load(other)).photos, [null, null, null, null]);
      expect(
        await attachDownloadedPhotos(history, 'JTDKN3DU0B1457686', [first]),
        0,
      );
    },
  );

  testWidgets(
    'workspace exposes both integrated tabs and retains inputs when switching',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = (await tester.runAsync(
        () => databaseFactoryMemory.openDatabase('automation-tabs'),
      ))!;
      addTearDown(db.close);
      final client = FakeAutomation();
      addTearDown(client.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: studioTheme(),
          home: WorkspaceScreen(
            history: PosterHistory(openDatabase: () => Future.value(db)),
            automation: client,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('studio-tab-photo-finder')));
      await tester.pumpAndSettle();
      expect(find.byType(PhotoFinderScreen), findsOneWidget);
      expect(find.text('Download photos'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('studio-tab-nca-import')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'NCA auction URL'),
        'https://my.nca.af/auction/view/test',
      );
      await tester.tap(find.byKey(const ValueKey('studio-tab-photo-finder')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('studio-tab-nca-import')));
      await tester.pumpAndSettle();
      expect(find.text('https://my.nca.af/auction/view/test'), findsOneWidget);
      await tester.ensureVisible(find.text('Publish to NCA'));
      await tester.tap(find.text('Publish to NCA'));
      await tester.pumpAndSettle();
      expect(find.text('Publish vehicles to NCA?'), findsOneWidget);
      expect(client.calls, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(client.calls, isEmpty);
    },
  );
}
