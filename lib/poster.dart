import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/services.dart';

class VehicleDetails {
  final String number;
  final String title;
  final String model;
  final String price;
  final String color;
  final String vin;

  const VehicleDetails({
    this.number = '',
    this.title = '',
    this.model = '',
    this.price = '',
    this.color = '',
    this.vin = '',
  });

  /// Raw editor values, separate from the formatted text used on the poster.
  Map<String, String> toJson() => {
    'number': number,
    'title': title,
    'model': model,
    'price': price,
    'color': color,
    'vin': vin,
  };

  factory VehicleDetails.fromJson(Map<String, Object?> json) => VehicleDetails(
    number: json['number'] as String? ?? '',
    title: json['title'] as String? ?? '',
    model: json['model'] as String? ?? '',
    price: json['price'] as String? ?? '',
    color: json['color'] as String? ?? '',
    vin: json['vin'] as String? ?? '',
  );

  Map<String, String> get fields {
    return {
      'number': number.trim(),

      'title': title.trim().toUpperCase(),

      'model': model.trim().toUpperCase(),

      'price': price.trim().isEmpty ? '' : '\$${price.trim()}',

      'typeColor': color.trim().toUpperCase(),

      'vin': vin.trim().toUpperCase(),
    };
  }
}

class GeneratedPoster {
  /// Used by flutter_svg in the preview.
  ///
  /// Photos and the logo are removed from this SVG because Flutter
  /// renders them separately using Image.memory.
  final String designSvg;

  /// Used when Share SVG is pressed.
  ///
  /// Vehicle images are embedded back into the SVG.
  final String exportSvg;

  final List<Uint8List?> photos;
  final Uint8List logo;

  const GeneratedPoster({
    required this.designSvg,
    required this.exportSvg,
    required this.photos,
    required this.logo,
  });
}

/// Shared geometry for the SVG export and the Flutter/PNG preview.
class PosterPhotoFrame {
  final int slot;
  final Rect bounds;
  final List<Offset> polygon;

  const PosterPhotoFrame(this.slot, this.bounds, this.polygon);

  String get placeholder => '{{vehiclePhoto$slot}}';

  Path clipPath(Size size) {
    return Path()..addPolygon([
      for (final point in polygon)
        Offset(
          (point.dx - bounds.left) * size.width / bounds.width,
          (point.dy - bounds.top) * size.height / bounds.height,
        ),
    ], true);
  }

  // Cropping and diagonal corners are already baked into the PNG pixels.
  // Importers only need to place the image at these explicit bounds.
  String svgImage(String uri) =>
      '<image id="vehicle-photo-$slot" x="${bounds.left}" y="${bounds.top}" '
      'width="${bounds.width}" height="${bounds.height}" '
      'preserveAspectRatio="none" href="$uri" xlink:href="$uri"/>';
}

class PosterTemplate {
  final String template;
  final Map<String, dynamic> originals;
  final Map<String, dynamic> fonts;
  final Uint8List logo;

  static const logoBounds = Rect.fromLTWH(121, 278, 287, 229);

  // Coordinates from the original template, including both main-photo cuts.
  static const photoFrames = [
    PosterPhotoFrame(0, Rect.fromLTRB(576.906, 676.563, 1574.99, 1773.08), [
      Offset(576.906, 924.045),
      Offset(863.965, 676.563),
      Offset(1574.99, 676.563),
      Offset(1574.99, 1699.57),
      Offset(1488.14, 1773.08),
      Offset(576.906, 1773.08),
    ]),
    PosterPhotoFrame(1, Rect.fromLTRB(60.1543, 551.082, 495.481, 944.342), [
      Offset(60.1543, 551.082),
      Offset(462.238, 551.082),
      Offset(495.481, 575.661),
      Offset(495.481, 944.342),
      Offset(60.1543, 944.342),
    ]),
    PosterPhotoFrame(2, Rect.fromLTRB(60.1543, 967.627, 495.481, 1355.71), [
      Offset(60.1543, 967.627),
      Offset(495.481, 967.627),
      Offset(495.481, 1355.71),
      Offset(60.1543, 1355.71),
    ]),
    PosterPhotoFrame(3, Rect.fromLTRB(60.1543, 1377.71, 495.481, 1770.97), [
      Offset(60.1543, 1377.71),
      Offset(495.481, 1377.71),
      Offset(495.481, 1770.97),
      Offset(60.1543, 1770.97),
    ]),
  ];

  static final _backgroundPath = RegExp(r'<path id="poster-background"[^>]*/>');

  /// Paint the template background behind the separately rendered photos.
  static String backgroundLayer(String svg) {
    final openingTag = svg.substring(0, svg.indexOf('>') + 1);
    final background = _backgroundPath.firstMatch(svg)!.group(0)!;
    final gradients = RegExp(
      r'<linearGradient\b.*?</linearGradient>',
      dotAll: true,
    ).allMatches(svg).map((match) => match.group(0)!).join();
    return '$openingTag$background<defs>$gradients</defs></svg>';
  }

  /// Keep the price badge, frame borders and decoration above the photos.
  static String foregroundLayer(String svg) =>
      svg.replaceFirst(_backgroundPath, '');

  PosterTemplate(this.template, this.originals, this.fonts, this.logo);

  static Future<PosterTemplate> load() async {
    var svg = await rootBundle.loadString('assets/template.svg');

    final logoTag = RegExp(
      r'<image\b[^>]*id="image3_2231_392"[^>]*/>',
    ).firstMatch(svg)!.group(0)!;
    final uri = RegExp(r'xlink:href="([^"]+)"').firstMatch(logoTag)!.group(1)!;
    final logo = await _rasterize(
      base64Decode(uri.substring(uri.indexOf(',') + 1)),
      logoBounds.size,
      // Preserve the original logo pattern's transform and vertical crop.
      source: const Rect.fromLTWH(
        0,
        0.126638 / 0.000999422,
        1 / 0.000797448,
        1 / 0.000999422,
      ),
    );
    svg = svg
        .replaceFirst(
          RegExp(r'<rect\b[^>]*fill="url\(#pattern3_2231_392\)"[^>]*/>'),
          '{{posterLogo}}',
        )
        .replaceFirst(logoTag, '')
        .replaceFirst(
          RegExp(r'<pattern id="pattern3_2231_392".*?</pattern>', dotAll: true),
          '',
        );

    final originalsJson = await rootBundle.loadString(
      'assets/original_text.json',
    );

    final fontsJson = await rootBundle.loadString('assets/glyphs.json');

    return PosterTemplate(
      svg,
      Map<String, dynamic>.from(jsonDecode(originalsJson)),
      Map<String, dynamic>.from(jsonDecode(fontsJson)),
      logo,
    );
  }

  static const Map<String, String> defaults = {
    'number': '2',
    'title': '2010 TOYOTA',
    'model': 'COROLLA',
    'price': '\$6000',
    'typeColor': 'S-CLASS SILVER',
    'vin': 'JTDKN3DU2A0090987',
  };

  static const Map<String, List<double>> specs = {
    'number': [285.747, 121.0, 100.0, 340.0],

    'title': [901.399, 146.0, 80.0, 1010.0],

    'model': [1008.511, 327.0, 170.0, 1030.0],

    'typeColor': [1042.897, 434.0, 70.0, 1010.0],

    'price': [729.393, 629.273, 96.0, 415.0],

    'vin': [1238.31, 607.2, 36.0, 400.0],
  };

  Future<GeneratedPoster> build(
    VehicleDetails details,
    List<Uint8List?> photos,
  ) async {
    var svg = template;

    // ================================================================
    // TEXT
    // ================================================================

    for (final entry in details.fields.entries) {
      final field = entry.key;
      final value = entry.value;

      String replacement = '';

      if (value.isEmpty) {
        replacement = '';
      } else if (value == defaults[field]) {
        replacement = originals[field]?.toString() ?? '';
      } else {
        try {
          replacement = _outline(field, value);
        } catch (_) {
          // Every field is optional.
          // Unsupported text should never block poster generation.
          replacement = '';
        }
      }

      svg = svg.replaceAll('{{$field}}', replacement);
    }

    final designSvg = svg.replaceAll('{{posterLogo}}', '');
    var previewSvg = designSvg;
    var exportSvg = svg.replaceAll(
      '{{posterLogo}}',
      '<image id="poster-logo" x="121" y="278" width="287" height="229" '
          'preserveAspectRatio="none" href="${_dataUri(logo)}"/>',
    );
    final preparedPhotos = List<Uint8List?>.filled(photoFrames.length, null);

    for (final frame in photoFrames) {
      previewSvg = previewSvg.replaceAll(frame.placeholder, '');
      final photo = frame.slot < photos.length ? photos[frame.slot] : null;
      var image = '';
      if (photo != null) {
        final prepared = await _rasterize(
          photo,
          frame.bounds.size,
          frame: frame,
        );
        preparedPhotos[frame.slot] = prepared;
        image = frame.svgImage(_dataUri(prepared));
      }
      // Slots are in the template's original paint order, below its borders
      // and price badge. No dependency on Figma's generated mask IDs.
      exportSvg = exportSvg.replaceAll(frame.placeholder, image);
    }

    return GeneratedPoster(
      designSvg: previewSvg,
      exportSvg: exportSvg,
      photos: List.unmodifiable(preparedPhotos),
      logo: logo,
    );
  }

  /// Rasterize once so preview, PNG and SVG use identical crop pixels.
  static Future<Uint8List> _rasterize(
    Uint8List bytes,
    Size size, {
    PosterPhotoFrame? frame,
    Rect? source,
  }) async {
    final codec = await instantiateImageCodec(bytes);
    Image? decoded;
    Image? output;
    Picture? picture;
    try {
      decoded = (await codec.getNextFrame()).image;
      final width = size.width.ceil();
      final height = size.height.ceil();
      final target = Size(width.toDouble(), height.toDouble());
      final scale = math.max(
        size.width / decoded.width,
        size.height / decoded.height,
      );
      final cropWidth = size.width / scale;
      final cropHeight = size.height / scale;
      final crop =
          source ??
          Rect.fromLTWH(
            (decoded.width - cropWidth) / 2,
            (decoded.height - cropHeight) / 2,
            cropWidth,
            cropHeight,
          );
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      if (frame != null) canvas.clipPath(frame.clipPath(target));
      canvas.drawImageRect(
        decoded,
        crop,
        Offset.zero & target,
        Paint()..filterQuality = FilterQuality.high,
      );
      picture = recorder.endRecording();
      output = await picture.toImage(width, height);
      final data = await output.toByteData(format: ImageByteFormat.png);
      if (data == null) throw StateError('Could not prepare poster image.');
      return data.buffer.asUint8List();
    } finally {
      output?.dispose();
      picture?.dispose();
      decoded?.dispose();
      codec.dispose();
    }
  }

  String _dataUri(Uint8List bytes) {
    // Image selection normalizes to PNG; preserve JPEG inputs for callers
    // that already have an encoded photograph.
    final isJpeg =
        bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff;
    final mimeType = isJpeg ? 'image/jpeg' : 'image/png';
    return 'data:$mimeType;base64,${base64Encode(bytes)}';
  }

  // ==================================================================
  // TEXT OUTLINE
  // ==================================================================

  String _outline(String field, String value) {
    final fontName = field == 'number' ? 'ExtraBold' : 'Bold';

    final dynamic rawFont = fonts[fontName];

    if (rawFont == null) {
      return '';
    }

    final font = Map<String, dynamic>.from(rawFont as Map);

    final glyphs = Map<String, dynamic>.from(font['glyphs'] as Map);

    final kern = Map<String, dynamic>.from(font['kern'] as Map);

    double cursor = 0;

    double minX = double.infinity;

    double maxX = double.negativeInfinity;

    final paths = StringBuffer();

    for (var i = 0; i < value.length; i++) {
      if (i > 0) {
        final pair = value.substring(i - 1, i + 1);

        cursor += (kern[pair] as num? ?? 0).toDouble();
      }

      final dynamic rawGlyph = glyphs[value[i]];

      if (rawGlyph == null) {
        continue;
      }

      final glyph = Map<String, dynamic>.from(rawGlyph as Map);

      final path = glyph['path']?.toString() ?? '';

      if (path.isNotEmpty) {
        final bounds = glyph['bounds'] as List<dynamic>;

        minX = math.min(minX, cursor + (bounds[0] as num).toDouble());

        maxX = math.max(maxX, cursor + (bounds[2] as num).toDouble());

        paths.write(
          '<path '
          'transform="translate($cursor 0)" '
          'd="$path"/>',
        );
      }

      cursor += (glyph['advance'] as num).toDouble();
    }

    if (!minX.isFinite || !maxX.isFinite) {
      return '';
    }

    final spec = specs[field];

    if (spec == null) {
      return '';
    }

    final units = (font['units'] as num).toDouble();

    final textWidth = maxX - minX;

    if (units <= 0 || textWidth <= 0) {
      return '';
    }

    final scale = math.min(spec[2] / units, spec[3] / textWidth);

    final x = spec[0] - (minX + maxX) * scale / 2;

    String fill = '#171716';

    if (field == 'number' || field == 'price') {
      fill = '#F5F1E6';
    }

    if (field == 'typeColor') {
      fill = '#B92A20';
    }

    return '''
<g
  fill="$fill"
  transform="translate($x ${spec[1]}) scale($scale ${-scale})">
  $paths
</g>
''';
  }
}
