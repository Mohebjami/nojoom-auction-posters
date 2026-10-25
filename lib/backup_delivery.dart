import 'dart:io';
import 'dart:ui';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

const backupFileType = XTypeGroup(
  label: 'Nojoom Studio backup',
  extensions: ['zip'],
  mimeTypes: ['application/zip'],
  uniformTypeIdentifiers: ['public.zip-archive'],
);

/// Returns no success message when the save or share is cancelled.
Future<String?> savePosterBackup(
  Uint8List bytes, {
  required Rect sharePositionOrigin,
}) async {
  final timestamp = DateTime.now()
      .toUtc()
      .toIso8601String()
      .replaceAll(':', '-')
      .replaceAll('.', '-');
  final name = 'nojoom-backup-$timestamp.zip';
  final file = XFile.fromData(bytes, name: name, mimeType: 'application/zip');
  if (kIsWeb) {
    await file.saveTo(name);
    return 'Backup download started. Check your browser downloads.';
  }
  if (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS) {
    final directory = await getTemporaryDirectory();
    final exportDirectory = await directory.createTemp('nojoom-backup-');
    final exportFile = File('${exportDirectory.path}/$name');
    await exportFile.writeAsBytes(bytes, flush: true);
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(exportFile.path, mimeType: 'application/zip')],
        fileNameOverrides: [name],
        title: 'Nojoom Studio backup',
        subject: 'Nojoom Studio backup',
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
    // Keep the temporary file available while a receiver copies the backup.
    return result.status == ShareResultStatus.success ? 'Backup shared.' : null;
  }
  final location = await getSaveLocation(
    suggestedName: name,
    acceptedTypeGroups: [backupFileType],
  );
  if (location == null) return null;
  await file.saveTo(location.path);
  return 'Backup saved.';
}
