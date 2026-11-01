import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
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
  final arguments = <Map<String, dynamic>>[];
  Map<String, dynamic>? posterPhotos;
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
    arguments.add(args);
    if (action == 'poster-photos') return posterPhotos!;
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
          null,
          first,
          second,
          null,
        ]),
        1,
      );
      final after = await history.load(id);
      expect(after.photos, [existing, first, second, existing]);
      expect(after.createdAt, before.createdAt);
      expect(after.updatedAt, before.updatedAt);
      expect(after.templateSvg, before.templateSvg);
      expect(after.templateName, before.templateName);
      expect(after.vehicle.price, '3000');
      expect((await history.load(other)).photos, [null, null, null, null]);
      expect(
        await attachDownloadedPhotos(history, 'JTDKN3DU0B1457686', [
          first,
          null,
          null,
          null,
        ]),
        0,
      );
    },
  );

  test(
    'missing interior does not shift side and rear photos and flags persist',
    () async {
      final db = await databaseFactoryMemory.openDatabase('missing-view');
      addTearDown(db.close);
      final history = PosterHistory(openDatabase: () async => db);
      final id = await history.save(
        const VehicleDetails(vin: 'JTDKN3DU0B1457686'),
        [null, null, null, null],
      );
      final side = Uint8List.fromList([3]);
      final rear = Uint8List.fromList([4]);
      expect(
        await attachDownloadedPhotos(history, 'JTDKN3DU0B1457686', [
          null,
          null,
          side,
          rear,
        ]),
        1,
      );
      expect((await history.load(id)).photos, [null, null, side, rear]);
      expect((await history.list()).single.missingPhotoSlots, [0, 1]);
      expect(
        await attachDownloadedPhotos(history, '', [rear, rear, rear, rear]),
        0,
      );
    },
  );

  testWidgets(
    'completed downloads attach automatically and keep manual photos',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = (await tester.runAsync(
        () => databaseFactoryMemory.openDatabase('auto-complete'),
      ))!;
      addTearDown(db.close);
      final history = PosterHistory(openDatabase: () async => db);
      final manual = Uint8List.fromList([42]);
      final id = (await tester.runAsync(
        () => history.save(const VehicleDetails(vin: 'JTDKN3DU0B1457686'), [
          manual,
          null,
          null,
          null,
        ]),
      ))!;
      final client = FakeAutomation();
      addTearDown(client.dispose);
      final png = base64Encode(img.encodePng(img.Image(width: 20, height: 20)));
      client.posterPhotos = {
        'vin': 'JTDKN3DU0B1457686',
        'photos': [png, null, png, png],
      };
      var changed = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: studioTheme(),
          home: Scaffold(
            body: PhotoFinderScreen(
              client: client,
              history: history,
              onLibraryChanged: () => changed++,
            ),
          ),
        ),
      );
      client.state['photos']['vehicles'] = [
        {
          'id': 'one',
          'missingViews': ['interior'],
          'vin': 'JTDKN3DU0B1457686',
          'status': 'done',
          'count': 4,
          'no': '1',
          'vehicle': '',
          'year': '',
        },
      ];
      await tester.runAsync(() async {
        client.notifyListeners();
        for (var i = 0; i < 30 && changed == 0; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pumpAndSettle();
      final draft = (await tester.runAsync(() => history.load(id)))!;
      expect(
        changed,
        1,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data ?? '')
            .join('\n'),
      );
      expect(draft.photos[0], manual);
      expect(draft.photos[1], isNull);
      expect(draft.photos[2], isNotNull);
      expect(draft.photos[3], isNotNull);
      expect(changed, 1);
      expect(client.calls, ['poster-photos']);
      client.notifyListeners();
      await tester.pumpAndSettle();
      expect(client.calls, ['poster-photos']);
      await tester.scrollUntilVisible(
        find.text('Needs attention'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Needs attention'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('photo-result-one')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester
            .widgetList<SelectableText>(find.byType(SelectableText))
            .any(
              (text) =>
                  text.data?.contains('Select manually: interior') == true,
            ),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a poster imported after downloads receives photos on library refresh',
    (tester) async {
      final db = (await tester.runAsync(
        () => databaseFactoryMemory.openDatabase('late-photo-draft'),
      ))!;
      addTearDown(db.close);
      final history = PosterHistory(openDatabase: () async => db);
      final signal = ValueNotifier<int>(0);
      addTearDown(signal.dispose);
      final client = FakeAutomation();
      addTearDown(client.dispose);
      client.state['photos']['vehicles'] = [
        {
          'id': 'late',
          'vin': 'JTDKN3DU0B1457686',
          'status': 'done',
          'count': 1,
          'no': '1',
          'vehicle': '',
          'year': '',
        },
      ];
      final png = base64Encode(img.encodePng(img.Image(width: 20, height: 20)));
      client.posterPhotos = {
        'vin': 'JTDKN3DU0B1457686',
        'photos': [png, null, null, null],
      };
      var changed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PhotoFinderScreen(
              client: client,
              history: history,
              refreshSignal: signal,
              onLibraryChanged: () => changed++,
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(client.calls, isEmpty);
      final id = (await tester.runAsync(
        () => history.save(const VehicleDetails(vin: 'JTDKN3DU0B1457686'), [
          null,
          null,
          null,
          null,
        ]),
      ))!;
      signal.value++;
      for (var i = 0; i < 30 && changed == 0; i++) {
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      await tester.pumpAndSettle();
      expect(
        changed,
        1,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data ?? '')
            .join('\n'),
      );
      expect(
        (await tester.runAsync(() => history.load(id)))!.photos[0],
        isNotNull,
      );
      expect(changed, 1);
      expect(client.calls, ['poster-photos']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'single VIN search works without a workbook and sends only this vehicle',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = (await tester.runAsync(
        () => databaseFactoryMemory.openDatabase('single-vin'),
      ))!;
      addTearDown(db.close);
      final client = FakeAutomation();
      addTearDown(client.dispose);
      client.state['photos']['filename'] = '';
      client.state['photos']['output'] = '/tmp/photos';
      await tester.pumpWidget(
        MaterialApp(
          theme: studioTheme(),
          home: Scaffold(
            body: PhotoFinderScreen(
              client: client,
              history: PosterHistory(openDatabase: () async => db),
              onLibraryChanged: () {},
            ),
          ),
        ),
      );
      await tester.enterText(
        find.byKey(const ValueKey('single-vehicle-vin')),
        'JTDKN3DU0B1457686',
      );
      await tester.enterText(
        find.byKey(const ValueKey('single-vehicle-number')),
        '25',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('find-single-vehicle')),
      );
      await tester.tap(find.byKey(const ValueKey('find-single-vehicle')));
      await tester.pumpAndSettle();
      expect(client.calls, ['photos.search-one']);
      expect(client.arguments.single, {'vin': 'JTDKN3DU0B1457686', 'no': '25'});
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
