import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:vehicle_poster/auction_vehicle.dart';
import 'package:vehicle_poster/backup_screen.dart';
import 'package:vehicle_poster/history_screen.dart';
import 'package:vehicle_poster/main.dart';
import 'package:vehicle_poster/poster.dart';
import 'package:vehicle_poster/poster_backup.dart';
import 'package:vehicle_poster/poster_history.dart';
import 'package:vehicle_poster/studio_ui.dart';

Future<void> settleBackup(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
  }
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/file_selector');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;
  late PosterHistory history;
  late File backupFile;
  late int imported;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('backup-ui-');
    imported = 0;
    final sourceDb = await databaseFactoryMemory.openDatabase(
      '${directory.path}/source',
    );
    final source = PosterHistory(openDatabase: () async => sourceDb);
    await source.save(
      const VehicleDetails(model: 'Corolla S Class', title: 'TOYOTA 2013'),
      [
        Uint8List.fromList([1, 2, 3]),
        null,
        null,
        null,
      ],
    );
    await source.createAuctionVehicle(
      const AuctionVehicle(vehicleType: 'Imported auction car'),
    );
    backupFile = File('${directory.path}/backup.zip');
    await backupFile.writeAsBytes(await source.exportBackup());
    await sourceDb.close();
    final targetDb = await databaseFactoryMemory.openDatabase(
      '${directory.path}/target',
    );
    addTearDown(targetDb.close);
    history = PosterHistory(openDatabase: () async => targetDb);
    await history.save(const VehicleDetails(model: 'Existing'), [
      null,
      null,
      null,
      null,
    ]);
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'openFile');
      return [backupFile.path];
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  Future<void> openScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        home: BackupScreen(history: history, onImported: () => imported++),
      ),
    );
  }

  testWidgets(
    'import previews counts, keeps data on cancel and adds copies on confirmation',
    (tester) async {
      await openScreen(tester);
      await tester.runAsync(
        () => tester.tap(find.byKey(const ValueKey('import-backup'))),
      );
      await settleBackup(tester);
      expect(find.text('Import this backup?'), findsOneWidget);
      expect(
        find.textContaining('1 saved posters, 1 images and 1 auction vehicles'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await settleBackup(tester);
      expect(await tester.runAsync(history.list), hasLength(1));
      expect(imported, 0);

      await tester.runAsync(
        () => tester.tap(find.byKey(const ValueKey('import-backup'))),
      );
      await settleBackup(tester);
      await tester.runAsync(
        () => tester.tap(find.widgetWithText(FilledButton, 'Import backup')),
      );
      await settleBackup(tester);
      expect(
        find.text('Imported 1 posters, 1 images and 1 auction vehicles.'),
        findsOneWidget,
      );
      expect(await tester.runAsync(history.list), hasLength(2));
      expect(await tester.runAsync(history.listAuctionVehicles), hasLength(1));
      expect(imported, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'invalid import reports failure and enables retry without changes',
    (tester) async {
      await tester.runAsync(() => backupFile.writeAsBytes([1, 2, 3]));
      await openScreen(tester);
      await tester.runAsync(
        () => tester.tap(find.byKey(const ValueKey('import-backup'))),
      );
      await settleBackup(tester);
      expect(find.textContaining('Could not import backup:'), findsOneWidget);
      expect(find.text('Import this backup?'), findsNothing);
      expect(await tester.runAsync(history.list), hasLength(1));
      expect(imported, 0);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const ValueKey('import-backup')))
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'export saves a readable backup and cancelled save reports no success',
    (tester) async {
      final output = File('${directory.path}/export.zip');
      var cancel = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'getSavePath');
        expect(call.arguments['suggestedName'], startsWith('nojoom-backup-'));
        expect(
          (call.arguments['acceptedTypeGroups'] as List).single['extensions'],
          ['zip'],
        );
        return cancel ? null : output.path;
      });
      await openScreen(tester);
      await tester.runAsync(
        () => tester.tap(find.byKey(const ValueKey('export-backup'))),
      );
      await settleBackup(tester);
      expect(find.text('Backup saved.'), findsOneWidget);
      final saved = await tester.runAsync(
        () async => PosterBackup.decode(await output.readAsBytes()),
      );
      expect(saved!.posters, hasLength(1));
      cancel = true;
      await tester.runAsync(
        () => tester.tap(find.byKey(const ValueKey('export-backup'))),
      );
      await settleBackup(tester);
      expect(find.text('Backup saved.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'History backup is available on mobile with an empty collection',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(
        () async =>
            history.deleteMany((await history.list()).map((entry) => entry.id)),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: studioTheme(),
          home: HistoryScreen(history: history),
        ),
      );
      await settleBackup(tester);
      final backupButton = find.byKey(const ValueKey('history-backup'));
      await tester.ensureVisible(backupButton);
      await tester.tap(backupButton);
      await tester.pumpAndSettle();
      expect(find.byType(BackupScreen), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('import-backup')));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('backup import refreshes an already visited auction workspace', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        home: WorkspaceScreen(history: history),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('studio-tab-auction-list')));
    await settleBackup(tester);
    expect(find.text('Imported auction car'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('studio-tab-history')));
    await settleBackup(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('history-backup')));
    await tester.tap(find.byKey(const ValueKey('history-backup')));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => tester.tap(find.byKey(const ValueKey('import-backup'))),
    );
    await settleBackup(tester);
    await tester.runAsync(
      () => tester.tap(find.widgetWithText(FilledButton, 'Import backup')),
    );
    await settleBackup(tester);
    await tester.tap(find.byTooltip('Back'));
    await settleBackup(tester);
    await tester.tap(find.byKey(const ValueKey('studio-tab-auction-list')));
    await settleBackup(tester);
    expect(find.text('Imported auction car'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
