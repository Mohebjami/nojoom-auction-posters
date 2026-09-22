import 'dart:convert';
import 'dart:typed_data';

import 'package:sembast/sembast.dart';

import 'auction_vehicle.dart';
import 'poster.dart';
import 'storage/database_native.dart'
    if (dart.library.js_interop) 'storage/database_web.dart';

abstract final class PosterSections {
  static const newVehicles = 'new';
  static const oldVehicles = 'old';

  static String normalize(Object? value) =>
      value == newVehicles ? newVehicles : oldVehicles;
}

class PosterDraft {
  final int id;
  final VehicleDetails vehicle;
  // Keep the original normalized images, before the poster's frame crops.
  final List<Uint8List?> photos;
  final String? templateSvg;
  final String? templateName;
  final String section;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PosterDraft({
    required this.id,
    required this.vehicle,
    required this.photos,
    required this.createdAt,
    required this.updatedAt,
    this.templateSvg,
    this.templateName,
    this.section = PosterSections.oldVehicles,
  });
}

class PosterHistoryEntry {
  final int id;
  final VehicleDetails vehicle;
  final DateTime updatedAt;
  final String section;

  const PosterHistoryEntry(
    this.id,
    this.vehicle,
    this.updatedAt, {
    this.section = PosterSections.oldVehicles,
  });

  String get title {
    final label = [
      vehicle.title,
      vehicle.model,
    ].where((part) => part.trim().isNotEmpty).join(' ');
    return label.isEmpty ? 'Untitled poster' : label;
  }
}

class PosterHistory {
  PosterHistory({Future<Database> Function()? openDatabase})
    : _openDatabase = openDatabase ?? openHistoryDatabase;

  static final instance = PosterHistory();
  final Future<Database> Function() _openDatabase;
  Future<Database>? _database;
  final _entries = intMapStoreFactory.store('entries');
  final _photos = intMapStoreFactory.store('photos');
  final _auctionVehicles = intMapStoreFactory.store('auction_vehicles');

  Future<Database> get _db async {
    try {
      return await (_database ??= _openDatabase());
    } catch (_) {
      _database = null; // Allow retry after a temporary storage failure.
      rethrow;
    }
  }

  Future<List<PosterHistoryEntry>> list() async {
    final records = await _entries.find(
      await _db,
      finder: Finder(sortOrders: [SortOrder('updatedAt', false)]),
    );
    return records
        .map(
          (record) => PosterHistoryEntry(
            record.key,
            VehicleDetails.fromJson(
              Map<String, Object?>.from(record.value['vehicle'] as Map),
            ),
            DateTime.parse(record.value['updatedAt'] as String),
            section: PosterSections.normalize(record.value['section']),
          ),
        )
        .toList();
  }

  Future<PosterDraft> load(int id) async {
    final db = await _db;
    return db.transaction((txn) async {
      final entry = await _entries.record(id).get(txn);
      final photos = await _photos.record(id).get(txn);
      if (entry == null || photos == null) {
        throw StateError('This saved poster is no longer available.');
      }
      return PosterDraft(
        id: id,
        vehicle: VehicleDetails.fromJson(
          Map<String, Object?>.from(entry['vehicle'] as Map),
        ),
        photos: (photos['slots'] as List)
            .map(
              (value) => value == null ? null : base64Decode(value as String),
            )
            .toList(),
        templateSvg: entry['templateSvg'] as String?,
        templateName: entry['templateName'] as String?,
        section: PosterSections.normalize(entry['section']),
        createdAt: DateTime.parse(entry['createdAt'] as String),
        updatedAt: DateTime.parse(entry['updatedAt'] as String),
      );
    });
  }

  Future<int> save(
    VehicleDetails vehicle,
    List<Uint8List?> photos, {
    int? id,
    String? templateSvg,
    String? templateName,
    String? section,
  }) async {
    if (photos.length != 4) {
      throw ArgumentError('A poster must contain exactly four photo slots.');
    }
    final encodedPhotos = photos
        .map((photo) => photo == null ? null : base64Encode(photo))
        .toList();
    final db = await _db;
    final now = DateTime.now().toUtc().toIso8601String();
    return db.transaction((txn) async {
      final previous = id == null ? null : await _entries.record(id).get(txn);
      if (id != null && previous == null) {
        throw StateError(
          'This poster was removed. Start a new poster to save a copy.',
        );
      }
      final entry = <String, Object?>{
        'version': 3,
        'templateSvg': templateSvg,
        'templateName': templateName,
        'section': PosterSections.normalize(
          section ??
              (previous == null
                  ? PosterSections.newVehicles
                  : previous['section']),
        ),
        'vehicle': vehicle.toJson(),
        'createdAt': previous?['createdAt'] ?? now,
        'updatedAt': now,
      };
      final key = id ?? await _entries.add(txn, entry);
      if (id != null) await _entries.record(key).put(txn, entry);
      await _photos.record(key).put(txn, {'slots': encodedPhotos});
      return key;
    });
  }

  Future<void> delete(int id) async {
    final db = await _db;
    await db.transaction((txn) async {
      await _entries.record(id).delete(txn);
      await _photos.record(id).delete(txn);
    });
  }

  /// Saves a vehicle in the separate auction-list workspace.
  ///
  /// Auction data deliberately has its own store so poster drafts keep their
  /// existing shape and users can maintain a complete auction list without
  /// creating a poster for every row.
  Future<int> createAuctionVehicle(AuctionVehicle vehicle) async {
    final now = DateTime.now().toUtc().toIso8601String();
    return _auctionVehicles.add(await _db, {
      'version': 1,
      'vehicle': vehicle.toJson(),
      'createdAt': now,
      'updatedAt': now,
    });
  }

  Future<void> updateAuctionVehicle(int id, AuctionVehicle vehicle) async {
    final db = await _db;
    await db.transaction((txn) async {
      final previous = await _auctionVehicles.record(id).get(txn);
      if (previous == null) {
        throw StateError('This auction vehicle is no longer available.');
      }
      await _auctionVehicles.record(id).put(txn, {
        'version': 1,
        'vehicle': vehicle.toJson(),
        'createdAt': previous['createdAt'],
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });
    });
  }

  Future<List<AuctionVehicleEntry>> listAuctionVehicles() async {
    final records = await _auctionVehicles.find(
      await _db,
      finder: Finder(sortOrders: [SortOrder('createdAt')]),
    );
    return records
        .map(
          (record) => AuctionVehicleEntry(
            id: record.key,
            vehicle: AuctionVehicle.fromJson(
              Map<String, Object?>.from(record.value['vehicle'] as Map),
            ),
            createdAt: DateTime.parse(record.value['createdAt'] as String),
            updatedAt: DateTime.parse(record.value['updatedAt'] as String),
          ),
        )
        .toList();
  }

  Future<void> deleteAuctionVehicle(int id) async {
    await _auctionVehicles.record(id).delete(await _db);
  }
}
