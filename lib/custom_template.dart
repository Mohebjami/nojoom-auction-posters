import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:xml/xml.dart';
import 'poster.dart';

/// Static SVG designs prepared with named vehicle-data placeholders.
class CustomPosterTemplate {
  final String name;
  final String source;
  final ui.Size size;
  const CustomPosterTemplate._(this.name, this.source, this.size);
  static final _token = RegExp(r'\{\{([^{}]+)\}\}');
  static const tokens = {
    'number',
    'title',
    'model',
    'price',
    'color',
    'vin',
    'photo0',
    'photo1',
    'photo2',
    'photo3',
    'logo',
  };
  static const _elements = {
    'svg',
    'g',
    'defs',
    'path',
    'rect',
    'circle',
    'ellipse',
    'line',
    'polyline',
    'polygon',
    'text',
    'tspan',
    'image',
    'clipPath',
    'mask',
    'linearGradient',
    'radialGradient',
    'stop',
    'pattern',
    'title',
    'desc',
  };

  factory CustomPosterTemplate.parse(String name, String source) {
    if (utf8.encode(source).length > 10 * 1024 * 1024) {
      throw const FormatException('Choose an SVG template smaller than 10 MB.');
    }
    if (source.contains('<!DOCTYPE') || source.contains('<!ENTITY')) {
      throw const FormatException(
        'Save the SVG without a DOCTYPE or external entities.',
      );
    }
    final doc = XmlDocument.parse(source);
    if (doc.rootElement.name.local != 'svg') {
      throw const FormatException('Choose an SVG template.');
    }
    final bounds = doc.rootElement
        .getAttribute('viewBox')
        ?.trim()
        .split(RegExp(r'[\s,]+'))
        .map(double.tryParse)
        .toList();
    if (bounds == null ||
        bounds.length != 4 ||
        bounds.any((v) => v == null || !v.isFinite) ||
        bounds[0] != 0 ||
        bounds[1] != 0 ||
        bounds[2]! < 1 ||
        bounds[3]! < 1 ||
        bounds[2]! > 4096 ||
        bounds[3]! > 4096 ||
        bounds[2]! * bounds[3]! > 8000000) {
      throw const FormatException(
        'Use viewBox="0 0 width height", up to 4096 per side and 8 million pixels.',
      );
    }
    final found = _token.allMatches(source).map((m) => m.group(1)!).toSet();
    if (found.isEmpty) {
      throw const FormatException(
        'Add data placeholders such as {{title}} and {{photo0}}. Try the sample template first.',
      );
    }
    if (found.difference(tokens).isNotEmpty) {
      throw FormatException(
        'Unknown placeholders: ${found.difference(tokens).join(', ')}.',
      );
    }
    for (final node in doc.descendants.whereType<XmlElement>()) {
      if (!_elements.contains(node.name.local)) {
        throw FormatException(
          'Unsupported SVG element: ${node.name.local}. Use static paths, text, and embedded images.',
        );
      }
      for (final attribute in node.attributes) {
        final value = attribute.value.trim();
        if (attribute.name.local.toLowerCase().startsWith('on')) {
          throw const FormatException('Remove scripts and event handlers.');
        }
        if (attribute.name.local == 'href' &&
            !(value.startsWith('#') ||
                value.startsWith('data:image/png;base64,') ||
                value.startsWith('data:image/jpeg;base64,') ||
                RegExp(r'^\{\{(photo[0-3]|logo)\}\}$').hasMatch(value))) {
          throw const FormatException(
            'Embed image files or use {{photo0}} to {{photo3}}. External links are not supported.',
          );
        }
        for (final url in RegExp(
          r'url\((.*?)\)',
          caseSensitive: false,
        ).allMatches(value)) {
          if (!url
              .group(1)!
              .replaceAll(RegExp('[\'"\\s]'), '')
              .startsWith('#')) {
            throw const FormatException(
              'SVG styles may only reference local gradients, masks, and clips.',
            );
          }
        }
        if (_token.hasMatch(value) &&
            !(node.name.local == 'image' &&
                attribute.name.local == 'href' &&
                RegExp(r'^\{\{(photo[0-3]|logo)\}\}$').hasMatch(value))) {
          throw const FormatException(
            'Put details inside text elements and photo placeholders in image href attributes.',
          );
        }
      }
      for (final text in node.children.whereType<XmlText>()) {
        if (_token.hasMatch(text.value) &&
            (!{'text', 'tspan'}.contains(node.name.local) ||
                _token
                    .allMatches(text.value)
                    .any(
                      (m) =>
                          m.group(1)!.startsWith('photo') ||
                          m.group(1) == 'logo',
                    ))) {
          throw const FormatException(
            'Put vehicle details inside text elements and photos in image href attributes.',
          );
        }
      }
    }
    return CustomPosterTemplate._(
      name,
      source,
      ui.Size(bounds[2]!, bounds[3]!),
    );
  }

  static Future<CustomPosterTemplate> sample() async =>
      CustomPosterTemplate.parse(
        'Clean showroom',
        await rootBundle.loadString('assets/templates/clean.svg'),
      );

  String populate(
    VehicleDetails details,
    List<Uint8List?> photos,
    Uint8List logo,
  ) {
    final doc = XmlDocument.parse(source);
    doc.rootElement.setAttribute('width', '${size.width.ceil()}');
    doc.rootElement.setAttribute('height', '${size.height.ceil()}');
    final fields = {...details.fields, 'color': details.fields['typeColor']!};
    for (final node in doc.descendants.whereType<XmlElement>().toList()) {
      for (final text in node.children.whereType<XmlText>()) {
        text.value = text.value.replaceAllMapped(
          _token,
          (m) => fields[m.group(1)] ?? '',
        );
      }
      if (node.name.local == 'text') {
        final width = double.tryParse(
          node.getAttribute('data-max-width') ?? '',
        );
        final fontSize = double.tryParse(
          node.getAttribute('font-size') ?? '16',
        );
        if (width != null &&
            width.isFinite &&
            width > 0 &&
            fontSize != null &&
            fontSize.isFinite &&
            fontSize > 0) {
          final weight = node.getAttribute('font-weight');
          final painter = TextPainter(
            text: TextSpan(
              text: node.innerText,
              style: TextStyle(
                fontSize: fontSize,
                fontFamily: node.getAttribute('font-family'),
                fontWeight: weight == 'bold' || weight == '700'
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          if (painter.width > width) {
            node.setAttribute(
              'font-size',
              '${fontSize * width / painter.width}',
            );
          }
          painter.dispose();
        }
      }
      if (node.name.local != 'image') continue;
      for (final attribute
          in node.attributes.where((a) => a.name.local == 'href').toList()) {
        final match = _token.firstMatch(attribute.value);
        if (match == null) continue;
        final key = match.group(1)!;
        final slot = key == 'logo' ? null : int.parse(key.substring(5));
        final bytes = slot == null
            ? logo
            : slot < photos.length
            ? photos[slot]
            : null;
        if (bytes == null || bytes.isEmpty) {
          node.parent?.children.remove(node);
          break;
        }
        final jpeg = bytes.length > 2 && bytes[0] == 0xff && bytes[1] == 0xd8;
        attribute.value =
            'data:image/${jpeg ? 'jpeg' : 'png'};base64,${base64Encode(bytes)}';
      }
    }
    return doc.toXmlString();
  }

  Future<GeneratedPoster> build(
    VehicleDetails details,
    List<Uint8List?> photos,
    Uint8List logo,
  ) async {
    final svg = populate(details, photos, logo);
    final picture = await vg.loadPicture(SvgStringLoader(svg), null);
    ui.Image? image;
    try {
      image = await picture.picture.toImage(
        size.width.ceil(),
        size.height.ceil(),
      );
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('Could not render this template.');
      return GeneratedPoster(
        designSvg: svg,
        exportSvg: svg,
        photos: const [],
        logo: Uint8List(0),
        previewImage: bytes.buffer.asUint8List(),
        canvasSize: size,
      );
    } finally {
      image?.dispose();
      picture.picture.dispose();
    }
  }
}
