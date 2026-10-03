import 'dart:io';
import 'dart:ui';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'batch_poster_export.dart';

/// Saves or shares a batch, returning a message only after a confirmed action.
/// A cancelled save, dismissed share, or unconfirmed share result returns null.
Future<String?> saveBatchPosterExport(
  BatchPosterExport export, {
  required Rect sharePositionOrigin,
}) async {
  final isPdf = export.mimeType == 'application/pdf';
  final format = isPdf ? 'PDF' : 'JPG ZIP';
  final file = XFile.fromData(
    export.bytes,
    name: export.fileName,
    mimeType: export.mimeType,
  );

  if (kIsWeb) {
    await file.saveTo(export.fileName);
    return '$format download started. Check your browser downloads.';
  }

  if (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS) {
    final temporaryDirectory = await getTemporaryDirectory();
    final exportDirectory = await temporaryDirectory.createTemp(
      'batch-poster-export-',
    );
    final exportFile = File('${exportDirectory.path}/${export.fileName}');
    await exportFile.writeAsBytes(export.bytes, flush: true);
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(exportFile.path, mimeType: export.mimeType)],
        fileNameOverrides: [export.fileName],
        title: 'Vehicle Posters',
        subject: 'Vehicle Posters',
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
    // Receivers may still be reading after the share sheet closes. Leave these
    // unique files in the system temporary directory for the OS to reclaim.
    if (result.status != ShareResultStatus.success) return null;
    return '$format shared.';
  }

  final location = await getSaveLocation(
    suggestedName: export.fileName,
    acceptedTypeGroups: [
      isPdf
          ? const XTypeGroup(
              label: 'PDF document',
              extensions: ['pdf'],
              mimeTypes: ['application/pdf'],
              uniformTypeIdentifiers: ['com.adobe.pdf'],
            )
          : const XTypeGroup(
              label: 'ZIP archive',
              extensions: ['zip'],
              mimeTypes: ['application/zip'],
              uniformTypeIdentifiers: ['public.zip-archive'],
            ),
    ],
  );
  if (location == null) return null;
  await file.saveTo(location.path);
  return '$format saved.';
}
