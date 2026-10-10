import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:vehicle_poster/poster.dart';
import 'package:vehicle_poster/poster_history.dart';
import 'package:vehicle_poster/vehicle_draft_import.dart';

void main() {
  late PosterHistory history;
  var databaseNumber = 0;
  setUp(() async {
    final db = await databaseFactoryMemory.openDatabase(
      'duplicate-import-${databaseNumber++}',
    );
    addTearDown(db.close);
    history = PosterHistory(openDatabase: () async => db);
  });

  Future<int> save(VehicleDetails vehicle) =>
      history.save(vehicle, [null, null, null, null]);

  test(
    'same vehicle on another import date creates a separate draft',
    () async {
      const vehicle = VehicleDetails(number: '1', vin: 'ABC', model: 'Prius');
      final firstDate = DateTime(2025, 1, 2, 23, 59);
      final nextDate = DateTime(2025, 1, 3, 0, 1);
      await history.importVehicleDetails([
        (id: null, vehicle: vehicle),
      ], importedAt: firstDate);
      final first = (await history.list()).single;
      final plan = (await VehicleDraftImportPlan.prepare(
        vehicles: const [vehicle],
        existing: await history.list(),
        importedAt: nextDate,
        resolveDuplicate: (_) async => throw StateError('Different day is new'),
      ))!;
      expect(plan.addedCount, 1);
      expect(plan.replacedCount, 0);
      expect(plan.drafts.single.id, isNull);
      await history.importVehicleDetails(plan.drafts, importedAt: nextDate);
      final entries = await history.list();
      expect(entries, hasLength(2));
      expect(
        entries.firstWhere((entry) => entry.id == first.id).labelDate,
        firstDate.toUtc(),
      );
      expect(
        entries.firstWhere((entry) => entry.id != first.id).labelDate,
        nextDate.toUtc(),
      );

      var conflicts = 0;
      final repeated = (await VehicleDraftImportPlan.prepare(
        vehicles: const [vehicle],
        existing: entries,
        importedAt: DateTime(2025, 1, 3, 18),
        resolveDuplicate: (conflict) async {
          conflicts++;
          expect(conflict.matches, hasLength(1));
          expect(conflict.matches.single.id, isNot(first.id));
          return const DuplicateImportDecision(DuplicateImportAction.skip);
        },
      ))!;
      expect(conflicts, 1);
      expect(repeated.skippedCount, 1);
      expect(repeated.drafts, isEmpty);
    },
  );

  test('repeated rows within a new-day import are still duplicates', () async {
    const vehicle = VehicleDetails(number: '1', vin: 'ABC');
    await history.importVehicleDetails([
      (id: null, vehicle: vehicle),
    ], importedAt: DateTime(2025, 1, 2));
    var conflicts = 0;
    final plan = (await VehicleDraftImportPlan.prepare(
      vehicles: const [vehicle, vehicle],
      existing: await history.list(),
      importedAt: DateTime(2025, 1, 3),
      resolveDuplicate: (conflict) async {
        conflicts++;
        expect(conflict.matches.single.id, isNull);
        expect(conflict.matches.single.importRow, 1);
        return const DuplicateImportDecision(DuplicateImportAction.skip);
      },
    ))!;
    expect(conflicts, 1);
    expect(plan.addedCount, 1);
    expect(plan.skippedCount, 1);
  });

  test(
    'matches VIN or number without case or surrounding whitespace',
    () async {
      final vinId = await save(const VehicleDetails(number: '1', vin: 'ABC'));
      final numberId = await save(const VehicleDetails(number: 'LOT-A'));
      final seen = <VehicleImportConflict>[];
      final plan = (await VehicleDraftImportPlan.prepare(
        vehicles: const [
          VehicleDetails(number: '2', vin: ' abc ', price: '9000'),
          VehicleDetails(number: ' lot-a ', color: 'Blue'),
          VehicleDetails(number: '3', vin: 'DEF'),
          VehicleDetails(model: 'No identifiers'),
          VehicleDetails(model: 'No identifiers'),
        ],
        existing: await history.list(),
        resolveDuplicate: (conflict) async {
          seen.add(conflict);
          return const DuplicateImportDecision(DuplicateImportAction.replace);
        },
      ))!;

      expect(seen.map((c) => c.matches.single.id), [vinId, numberId]);
      expect(plan.addedCount, 3);
      expect(plan.replacedCount, 2);
      await history.importVehicleDetails(plan.drafts);
      expect(await history.list(), hasLength(5));
      expect((await history.load(vinId)).vehicle.price, '9000');
      expect((await history.load(numberId)).vehicle.color, 'Blue');
    },
  );

  test(
    'replacement keeps identity, photos, template and creation time',
    () async {
      final photos = [
        Uint8List.fromList([1, 2, 3]),
        null,
        null,
        null,
      ];
      final id = await history.save(
        const VehicleDetails(number: '1', vin: 'ABC', price: '6000'),
        photos,
        templateSvg: '<svg/>',
        templateName: 'Custom',
      );
      final before = await history.load(id);
      final plan = (await VehicleDraftImportPlan.prepare(
        vehicles: const [
          VehicleDetails(number: '1', vin: 'ABC', price: '7000'),
        ],
        existing: await history.list(),
        resolveDuplicate: (_) async =>
            const DuplicateImportDecision(DuplicateImportAction.replace),
      ))!;
      await history.importVehicleDetails(plan.drafts);
      final after = await history.load(id);
      expect(await history.list(), hasLength(1));
      expect(after.vehicle.price, '7000');
      expect(after.photos, photos);
      expect(after.templateSvg, '<svg/>');
      expect(after.templateName, 'Custom');
      expect(after.createdAt, before.createdAt);
      expect(after.section, PosterSections.oldVehicles);
    },
  );

  test('skip all keeps originals and imports unrelated new rows', () async {
    final id = await save(const VehicleDetails(number: '1', vin: 'ABC'));
    final before = await history.load(id);
    var prompts = 0;
    final plan = (await VehicleDraftImportPlan.prepare(
      vehicles: const [
        VehicleDetails(number: '1', vin: 'SKIPPED', price: '7000'),
        VehicleDetails(number: '1', vin: 'ABC', price: '8000'),
        VehicleDetails(number: '2', vin: 'SKIPPED'),
      ],
      existing: await history.list(),
      resolveDuplicate: (_) async {
        prompts++;
        return const DuplicateImportDecision(
          DuplicateImportAction.skip,
          applyToRemaining: true,
        );
      },
    ))!;
    await history.importVehicleDetails(plan.drafts);
    expect(prompts, 1);
    expect(plan.skippedCount, 2);
    expect(plan.addedCount, 1);
    expect(await history.list(), hasLength(2));
    final after = await history.load(id);
    expect(after.vehicle.toJson(), before.vehicle.toJson());
    expect(after.updatedAt, before.updatedAt);
  });

  test('replace all handles repeated rows in the same import', () async {
    var prompts = 0;
    final plan = (await VehicleDraftImportPlan.prepare(
      vehicles: const [
        VehicleDetails(number: '1', vin: 'ABC', price: '6000'),
        VehicleDetails(number: '1', vin: 'DEF', price: '7000'),
        VehicleDetails(number: '2', vin: 'DEF', price: '8000'),
        // The old VIN is no longer a duplicate after replacement.
        VehicleDetails(number: '3', vin: 'ABC'),
      ],
      existing: [],
      resolveDuplicate: (conflict) async {
        prompts++;
        expect(conflict.matches.single.importRow, 1);
        expect(conflict.matches.single.id, isNull);
        return const DuplicateImportDecision(
          DuplicateImportAction.replace,
          applyToRemaining: true,
        );
      },
    ))!;
    expect(prompts, 1);
    expect(plan.addedCount, 2);
    expect(plan.replacedCount, 2);
    await history.importVehicleDetails(plan.drafts);
    final entries = await history.list();
    expect(entries, hasLength(2));
    expect(entries.map((e) => e.vehicle.price), contains('8000'));
  });

  test(
    'ambiguous replacements still ask which saved entry to update',
    () async {
      final first = await save(const VehicleDetails(number: '1', vin: 'AAA'));
      final second = await save(const VehicleDetails(number: '2', vin: 'BBB'));
      var prompts = 0;
      final plan = (await VehicleDraftImportPlan.prepare(
        vehicles: const [
          VehicleDetails(number: '1', vin: 'AAA', price: '7000'),
          VehicleDetails(number: '1', vin: 'BBB', price: '8000'),
        ],
        existing: await history.list(),
        resolveDuplicate: (conflict) async {
          prompts++;
          return DuplicateImportDecision(
            DuplicateImportAction.replace,
            matchIndex: prompts == 1
                ? 0
                : conflict.matches.indexWhere((match) => match.id == second),
            applyToRemaining: true,
          );
        },
      ))!;
      expect(prompts, 2);
      await history.importVehicleDetails(plan.drafts);
      expect((await history.load(first)).vehicle.price, '7000');
      expect((await history.load(second)).vehicle.price, '8000');
    },
  );

  test('cancel discards new rows and earlier replacement decisions', () async {
    final id = await save(const VehicleDetails(number: '1', price: '6000'));
    var prompts = 0;
    final plan = await VehicleDraftImportPlan.prepare(
      vehicles: const [
        VehicleDetails(number: '2'),
        VehicleDetails(number: '1', price: '7000'),
        VehicleDetails(number: '1', price: '8000'),
      ],
      existing: await history.list(),
      resolveDuplicate: (_) async => DuplicateImportDecision(
        ++prompts == 1
            ? DuplicateImportAction.replace
            : DuplicateImportAction.cancel,
      ),
    );
    expect(plan, isNull);
    expect(await history.list(), hasLength(1));
    expect((await history.load(id)).vehicle.price, '6000');
  });

  test('failed import rolls back all writes if a target disappeared', () async {
    final id = await save(const VehicleDetails(number: '1', price: '6000'));
    await expectLater(
      history.importVehicleDetails([
        (id: null, vehicle: const VehicleDetails(number: '2')),
        (id: id, vehicle: const VehicleDetails(number: '1', price: '7000')),
        (id: id + 100, vehicle: const VehicleDetails(number: '3')),
      ]),
      throwsStateError,
    );
    expect(await history.list(), hasLength(1));
    expect((await history.load(id)).vehicle.price, '6000');
  });
}
