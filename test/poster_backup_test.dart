import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sembast/sembast_memory.dart';
import 'package:sembast/sembast_io.dart';
import 'package:vehicle_poster/auction_vehicle.dart';
import 'package:vehicle_poster/poster.dart';
import 'package:vehicle_poster/poster_backup.dart';
import 'package:vehicle_poster/poster_history.dart';

Uint8List zipJson(Map<String, Object?> json) => Uint8List.fromList(
  ZipEncoder().encode(
    Archive()
      ..add(ArchiveFile.string(PosterBackup.manifestName, jsonEncode(json))),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const vehicle = VehicleDetails(
    number: '009',
    title: 'TOYOTA 2013',
    model: 'Corolla S Class',
    color: 'نقره‌ای',
    price: '6000.50',
    vin: 'VIN-009',
  );
  const auction = AuctionVehicle(
    number: '07',
    vin: 'AUCTION-VIN',
    vehicleType: 'Prius',
    year: '2015',
    mileage: '95000',
    color: 'White',
    owner: 'مالک',
    redLight: '4000',
    greenLight: '4500',
    priceUsd: '5000.50',
  );

  test(
    'ZIP round trip preserves all stores, original images and dates on disk',
    () async {
      final sourceDb = await databaseFactoryMemory.openDatabase(
        'backup-source',
      );
      addTearDown(sourceDb.close);
      final source = PosterHistory(openDatabase: () async => sourceDb);
      final photo = img.encodePng(img.Image(width: 20, height: 30));
      final photos = [photo, null, photo, photo];
      const template =
          '<svg viewBox="0 0 100 100"><text>{{title}}</text></svg>';
      final id = await source.save(
        vehicle,
        photos,
        templateSvg: template,
        templateName: 'My template',
      );
      final importedAt = DateTime.utc(2020, 2, 3);
      await source.importVehicleDetails([
        (id: id, vehicle: vehicle),
      ], importedAt: importedAt);
      final old = await source.load(id);
      await source.save(const VehicleDetails(number: '10'), [
        null,
        null,
        null,
        null,
      ]);
      await source.createAuctionVehicle(auction);
      final sourceAuction = (await source.listAuctionVehicles()).single;

      final bytes = await source.exportBackup();
      expect(bytes.take(2), [0x50, 0x4b]);
      final backup = PosterBackup.decode(bytes);
      expect(backup.posters, hasLength(2));
      expect(backup.photoCount, 3);
      expect(backup.auctionVehicles, hasLength(1));

      final directory = await Directory.systemTemp.createTemp(
        'backup-restore-',
      );
      final databasePath = '${directory.path}/restored.db';
      var targetDb = await databaseFactoryIo.openDatabase(databasePath);
      addTearDown(() async {
        await targetDb.close();
        await directory.delete(recursive: true);
      });
      var target = PosterHistory(openDatabase: () async => targetDb);
      final existingId = await target.save(
        const VehicleDetails(model: 'Existing'),
        photos,
      );
      await target.createAuctionVehicle(const AuctionVehicle(vin: 'EXISTING'));
      await target.importBackup(backup);
      await targetDb.close();
      targetDb = await databaseFactoryIo.openDatabase(databasePath);
      target = PosterHistory(openDatabase: () async => targetDb);

      final entries = await target.list();
      expect(entries, hasLength(3));
      expect((await target.load(existingId)).vehicle.model, 'Existing');
      final restoredEntry = entries.singleWhere(
        (entry) => entry.vehicle.vin == vehicle.vin,
      );
      expect(restoredEntry.id, isNot(existingId));
      expect(restoredEntry.labelDate, importedAt);
      final restored = await target.load(restoredEntry.id);
      expect(restored.vehicle.toJson(), vehicle.toJson());
      expect(restored.photos, photos);
      expect(restored.templateSvg, template);
      expect(restored.templateName, 'My template');
      expect(restored.section, PosterSections.oldVehicles);
      expect(restored.createdAt, old.createdAt);
      expect(restored.updatedAt, old.updatedAt);
      expect(
        entries.singleWhere((entry) => entry.vehicle.number == '10').section,
        PosterSections.newVehicles,
      );
      final restoredAuction = (await target.listAuctionVehicles()).singleWhere(
        (entry) => entry.vehicle.vin == auction.vin,
      );
      expect(restoredAuction.vehicle.toJson(), auction.toJson());
      expect(restoredAuction.createdAt, sourceAuction.createdAt);
      expect(restoredAuction.updatedAt, sourceAuction.updatedAt);

      // Re-exporting a restored workspace remains compatible.
      final again = PosterBackup.decode(await target.exportBackup());
      expect(again.posters, hasLength(3));
      expect(again.photoCount, 6);
      expect(again.auctionVehicles, hasLength(2));
    },
  );

  test(
    'empty workspace backup is valid and imports without deleting existing data',
    () async {
      final db = await databaseFactoryMemory.openDatabase('backup-empty');
      addTearDown(db.close);
      final history = PosterHistory(openDatabase: () async => db);
      final empty = PosterBackup.decode(await history.exportBackup());
      expect(empty.posters, isEmpty);
      expect(empty.auctionVehicles, isEmpty);
      expect(empty.photoCount, 0);
      await history.save(vehicle, [null, null, null, null]);
      await history.importBackup(empty);
      expect(await history.list(), hasLength(1));
    },
  );

  test(
    'invalid last record is rejected before any poster or auction writes',
    () async {
      final db = await databaseFactoryMemory.openDatabase('backup-invalid');
      addTearDown(db.close);
      final history = PosterHistory(openDatabase: () async => db);
      await history.save(vehicle, [null, null, null, null]);
      await history.createAuctionVehicle(auction);
      final backup = PosterBackup.decode(await history.exportBackup());
      backup.auctionVehicles.last['updatedAt'] = 'not a date';
      await expectLater(history.importBackup(backup), throwsFormatException);
      expect(await history.list(), hasLength(1));
      expect(await history.listAuctionVehicles(), hasLength(1));
    },
  );

  test(
    'rejects malformed photo slots, invalid base64 and future versions',
    () async {
      final db = await databaseFactoryMemory.openDatabase('backup-validation');
      addTearDown(db.close);
      final history = PosterHistory(openDatabase: () async => db);
      await history.save(vehicle, [
        Uint8List.fromList([1, 2]),
        null,
        null,
        null,
      ]);
      final bytes = await history.exportBackup();
      Map<String, Object?> fresh() => PosterBackup.decode(bytes).toJson();
      final badSlots = fresh();
      ((badSlots['posters'] as List).single as Map)['photos'] = [null];
      final badImage = fresh();
      (((badImage['posters'] as List).single as Map)['photos'] as List)[0] =
          '!!!';
      final futureRecord = fresh();
      (((futureRecord['posters'] as List).single as Map)['entry']
              as Map)['version'] =
          99;
      final badVehicle = fresh();
      ((((badVehicle['posters'] as List).single as Map)['entry']
                  as Map)['vehicle']
              as Map)['model'] =
          5;
      final missingPhotos = fresh();
      ((missingPhotos['posters'] as List).single as Map).remove('photos');
      for (final data in [
        badSlots,
        badImage,
        futureRecord,
        badVehicle,
        missingPhotos,
        {...fresh(), 'version': 99},
        {...fresh(), 'format': 'another-app'},
      ]) {
        expect(() => PosterBackup.decode(zipJson(data)), throwsFormatException);
      }
      expect(await history.list(), hasLength(1));
    },
  );

  test('damaged ZIP and unrelated archive cannot be imported', () async {
    expect(
      () => PosterBackup.decode(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
    final unrelated = Archive()
      ..add(ArchiveFile.string('image.png', 'example'));
    expect(
      () => PosterBackup.decode(
        Uint8List.fromList(ZipEncoder().encode(unrelated)),
      ),
      throwsFormatException,
    );
    final json = {
      'format': PosterBackup.format,
      'version': 1,
      'createdAt': DateTime.utc(2025).toIso8601String(),
      'posters': [],
      'auctionVehicles': [],
    };
    final damaged = zipJson(json);
    // Corrupt the checksum in the ZIP central directory.
    for (var index = 0; index < damaged.length - 20; index++) {
      if (damaged[index] == 0x50 &&
          damaged[index + 1] == 0x4b &&
          damaged[index + 2] == 1 &&
          damaged[index + 3] == 2) {
        damaged[index + 16] ^= 0xff;
        break;
      }
    }
    expect(() => PosterBackup.decode(damaged), throwsFormatException);
  });
}
