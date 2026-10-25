import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:vehicle_poster/history_screen.dart';
import 'package:vehicle_poster/poster.dart';
import 'package:vehicle_poster/poster_history.dart';
import 'package:vehicle_poster/vehicle_draft_import.dart';
import 'package:vehicle_poster/vehicle_duplicate_review.dart';

PosterHistoryEntry entry(int id, String vin, int day, {int? editedDay}) =>
    PosterHistoryEntry(
      id,
      VehicleDetails(number: '$id', vin: vin, price: '${id * 1000}'),
      DateTime(2025, 1, editedDay ?? day),
      labelDate: DateTime(2025, 1, day),
    );

Future<void> settleStorage(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  // A busy indicator animates behind the review dialog.
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  for (final action in [
    DuplicateImportAction.keepBoth,
    DuplicateImportAction.replace,
    DuplicateImportAction.skip,
  ]) {
    test('existing VIN groups support $action across dates', () async {
      var prompts = 0;
      final plan = (await VehicleDuplicateReviewPlan.prepare(
        existing: [
          entry(3, 'ABC', 3),
          entry(1, ' abc ', 1, editedDay: 9),
          entry(2, 'Abc', 2),
          entry(4, 'DEF', 1),
          entry(5, ' def ', 2),
          entry(6, '', 1),
          entry(7, ' ', 1),
          entry(8, 'UNIQUE', 1),
        ],
        resolveDuplicate: (conflict) async {
          prompts++;
          expect(conflict.incoming.number, '3');
          expect(conflict.matches.map((match) => match.id), [1, 2]);
          return DuplicateImportDecision(action, applyToRemaining: true);
        },
      ))!;
      expect(prompts, 1);
      expect(plan.duplicateGroups, 2);
      expect(
        plan.deletedIds,
        unorderedEquals(switch (action) {
          DuplicateImportAction.replace => [1, 2, 4],
          DuplicateImportAction.skip => [2, 3, 5],
          _ => <int>[],
        }),
      );
    });
  }

  test('cancel discards earlier cleanup decisions', () async {
    var prompts = 0;
    final plan = await VehicleDuplicateReviewPlan.prepare(
      existing: [
        entry(1, 'ABC', 1),
        entry(2, 'ABC', 2),
        entry(3, 'DEF', 1),
        entry(4, 'DEF', 2),
      ],
      resolveDuplicate: (_) async => DuplicateImportDecision(
        ++prompts == 1
            ? DuplicateImportAction.replace
            : DuplicateImportAction.cancel,
      ),
    );
    expect(prompts, 2);
    expect(plan, isNull);
  });

  test('blank VINs do not form a duplicate group', () async {
    final plan = (await VehicleDuplicateReviewPlan.prepare(
      existing: [entry(1, '', 1), entry(2, ' ', 1), entry(3, 'ABC', 1)],
      resolveDuplicate: (_) async => throw StateError('No duplicates'),
    ))!;
    expect(plan.duplicateGroups, 0);
    expect(plan.deletedIds, isEmpty);
  });

  for (final action in [
    'Keep both',
    'Keep previous',
    'Replace with new',
    'Cancel review',
  ]) {
    testWidgets('History button reviews stored duplicates: $action', (
      tester,
    ) async {
      final db = (await tester.runAsync(
        () => databaseFactoryMemory.openDatabase('review-$action'),
      ))!;
      addTearDown(db.close);
      final history = PosterHistory(openDatabase: () async => db);
      await tester.runAsync(() async {
        for (final day in [1, 2, 3]) {
          await history.importVehicleDetails([
            (id: null, vehicle: VehicleDetails(number: '$day', vin: 'ABC')),
          ], importedAt: DateTime(2025, 1, day));
        }
      });
      final saved = (await tester.runAsync(history.list))!;
      final newestId = saved.singleWhere((e) => e.vehicle.number == '3').id;
      final oldestId = saved.singleWhere((e) => e.vehicle.number == '1').id;
      // Retaining a saved entry must retain its own photos and template.
      final photos = [
        Uint8List.fromList([1, 2, 3]),
        null,
        null,
        null,
      ];
      await tester.runAsync(
        () => history.save(
          saved.singleWhere((e) => e.id == newestId).vehicle,
          photos,
          id: newestId,
          templateSvg: '<svg/>',
          templateName: 'Newest template',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: HistoryScreen(history: history, embedded: true)),
        ),
      );
      await settleStorage(tester);
      final button = find.byKey(const ValueKey('history-find-vin-duplicates'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await settleStorage(tester);
      expect(find.text('3 saved entries share this VIN.'), findsOneWidget);
      expect((await tester.runAsync(history.list))!, hasLength(3));
      await tester.ensureVisible(find.text(action));
      await tester.tap(find.text(action));
      await settleStorage(tester);
      final after = (await tester.runAsync(history.list))!;
      if (action == 'Keep previous' || action == 'Replace with new') {
        expect(after, hasLength(1));
        expect(
          after.single.id,
          action == 'Keep previous' ? oldestId : newestId,
        );
      } else {
        expect(after, hasLength(3));
      }
      if (action != 'Keep previous') {
        final draft = (await tester.runAsync(() => history.load(newestId)))!;
        expect(draft.photos, photos);
        expect(draft.templateName, 'Newest template');
      }
      expect(find.text('Duplicate vehicle found'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
    });
  }
}
