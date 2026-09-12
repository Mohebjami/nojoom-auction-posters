import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Encode a real JPEG and flatten transparency onto white.
/// Top-level so Flutter's compute can run it off the UI isolate on devices.
Uint8List encodePosterJpg(Uint8List png) {
  final decoded = img.decodePng(png);
  if (decoded == null) throw const FormatException('Could not decode poster.');
  final background = img.Image(width: decoded.width, height: decoded.height);
  img.fill(background, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(background, decoded);
  return img.encodeJpg(background, quality: 95);
}
