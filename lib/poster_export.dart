import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:xml/xml.dart';

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

/// Lossless optimization for sharing. Retains vectors, dimensions, and alpha.
/// Native callers use compute so PNG encoding does not block the UI.
Uint8List compressPosterSvg(String svg) {
  final original = Uint8List.fromList(utf8.encode(svg));
  final document = XmlDocument.parse(svg);
  final cache = <String, String>{};
  for (final node in document.descendants.whereType<XmlElement>().where(
    (e) => e.name.local == 'image',
  )) {
    for (final attribute
        in node.attributes.where((a) => a.name.local == 'href').toList()) {
      final uri = attribute.value;
      attribute.value = cache.putIfAbsent(uri, () {
        const prefix = 'data:image/png;base64,';
        if (!uri.startsWith(prefix)) return uri;
        try {
          final bytes = base64Decode(uri.substring(prefix.length));
          final decoded = img.decodePng(bytes);
          if (decoded == null || decoded.numFrames != 1) return uri;
          final compressed = img.encodePng(decoded, level: 9);
          return compressed.length < bytes.length
              ? '$prefix${base64Encode(compressed)}'
              : uri;
        } on FormatException {
          return uri;
        }
      });
    }
    final href = node.getAttribute('href');
    if (href != null) {
      node.attributes.removeWhere(
        (a) => a.name.qualified == 'xlink:href' && a.value == href,
      );
    }
  }
  final result = Uint8List.fromList(utf8.encode(document.toXmlString()));
  return result.length < original.length ? result : original;
}
