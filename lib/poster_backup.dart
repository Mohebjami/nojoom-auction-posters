import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Versioned, portable data. Photos retain their original bytes and slot order.
class PosterBackup {
  static const format = 'nojoom-studio-backup';
  static const version = 1;
  static const manifestName = 'backup.json';

  final DateTime createdAt;
  final List<Map<String, Object?>> posters;
  final List<Map<String, Object?>> auctionVehicles;

  PosterBackup._(this.createdAt, this.posters, this.auctionVehicles);

  int get photoCount => posters.fold(
    0,
    (count, poster) =>
        count + (poster['photos'] as List).whereType<String>().length,
  );

  Map<String, Object?> toJson() => {
    'format': format,
    'version': version,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'posters': posters,
    'auctionVehicles': auctionVehicles,
  };

  /// Validate everything before opening a write transaction.
  factory PosterBackup.fromJson(Map<String, Object?> json) {
    if (json['format'] != format) {
      throw const FormatException('Choose a Nojoom Studio backup ZIP.');
    }
    if (json['version'] != version) {
      throw const FormatException(
        'This backup version is not supported. Update the app and try again.',
      );
    }
    final createdAt = _date(json['createdAt']);
    final posters = _records(json['posters']);
    final auctionVehicles = _records(json['auctionVehicles']);
    for (final poster in posters) {
      final entry = _map(poster['entry']);
      _validateEntry(entry, maxVersion: 3);
      _validateVehicle(entry['vehicle'], const [
        'number',
        'title',
        'model',
        'price',
        'color',
        'vin',
      ]);
      for (final key in ['templateSvg', 'templateName']) {
        if (entry[key] != null && entry[key] is! String) _invalid();
      }
      if (entry['labelDate'] != null) _date(entry['labelDate']);
      if (entry['section'] != null &&
          entry['section'] != 'new' &&
          entry['section'] != 'old') {
        _invalid();
      }
      final photos = poster['photos'];
      if (photos is! List || photos.length != 4) _invalid();
      for (final photo in photos) {
        if (photo == null) continue;
        if (photo is! String || photo.isEmpty) _invalid();
        base64Decode(photo);
      }
    }
    for (final entry in auctionVehicles) {
      _validateEntry(entry, maxVersion: 1);
      _validateVehicle(entry['vehicle'], const [
        'number',
        'vin',
        'vehicleType',
        'year',
        'mileage',
        'color',
        'owner',
        'redLight',
        'greenLight',
        'priceUsd',
      ]);
    }
    return PosterBackup._(createdAt, posters, auctionVehicles);
  }

  static Uint8List encode(PosterBackup backup) {
    final archive = Archive()
      ..add(ArchiveFile.string(manifestName, jsonEncode(backup.toJson())));
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  static PosterBackup decode(Uint8List bytes) {
    try {
      final decoder = ZipDecoder();
      final archive = decoder.decodeBytes(bytes);
      final manifest = archive.findFile(manifestName);
      if (manifest == null || !manifest.isFile) {
        throw const FormatException('Choose a Nojoom Studio backup ZIP.');
      }
      final content = manifest.content;
      final headers = decoder.directory.fileHeaders
          .where((header) => header.filename == manifestName)
          .toList();
      // Verify explicitly: archive's ZIP decoder does not check CRC itself.
      final checksum = getCrc32(content);
      if (headers.length != 1 ||
          content.length != manifest.size ||
          checksum != manifest.crc32 ||
          checksum != headers.single.crc32) {
        throw const FormatException(
          'This backup is damaged. Choose another backup file.',
        );
      }
      return PosterBackup.fromJson(_map(jsonDecode(utf8.decode(content))));
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
        'Could not read this backup. Choose a valid Nojoom Studio backup ZIP.',
      );
    }
  }

  static void _validateEntry(
    Map<String, Object?> entry, {
    required int maxVersion,
  }) {
    final recordVersion = entry['version'];
    if (recordVersion is! int || recordVersion < 1) _invalid();
    if (recordVersion > maxVersion) {
      throw const FormatException(
        'This backup contains newer data. Update the app and try again.',
      );
    }
    _date(entry['createdAt']);
    _date(entry['updatedAt']);
  }

  static void _validateVehicle(Object? value, List<String> fields) {
    final vehicle = _map(value);
    for (final field in fields) {
      if (vehicle[field] != null && vehicle[field] is! String) _invalid();
    }
  }

  static Map<String, Object?> _map(Object? value) {
    if (value is! Map || value.keys.any((key) => key is! String)) _invalid();
    return Map<String, Object?>.from(value);
  }

  static List<Map<String, Object?>> _records(Object? value) {
    if (value is! List) _invalid();
    return value.map(_map).toList();
  }

  static DateTime _date(Object? value) {
    if (value is! String) _invalid();
    final date = DateTime.tryParse(value);
    if (date == null) _invalid();
    return date;
  }

  static Never _invalid() => throw const FormatException(
    'This backup contains incomplete or invalid data. Nothing was imported.',
  );
}
