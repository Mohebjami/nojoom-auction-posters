import 'dart:typed_data';

import 'package:gal/gal.dart';

Future<void> ensureGalleryAccess() async {
  if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
    throw StateError(
      'Photo access was denied. Allow photo saving in your device settings and try again.',
    );
  }
}

Future<void> saveJpgToGallery(Uint8List bytes, String fileName) =>
    Gal.putImageBytes(
      bytes,
      name: fileName.replaceFirst(RegExp(r'\.jpg$'), ''),
    );
