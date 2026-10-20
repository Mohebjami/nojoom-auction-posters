import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pdf/pdf.dart';
import 'package:xml/xml.dart';

/// Rasterize text with Flutter so Persian shaping and system font fallback are
/// preserved. The SVG renderer does not support SVG text elements itself.
Future<Uint8List> renderVehicleLabel(String svg) async {
  final document = XmlDocument.parse(svg);
  // Use template coordinates rather than its physical millimeter dimensions.
  document.rootElement
    ..setAttribute('width', '1109')
    ..setAttribute('height', '1418');
  for (final text in document.findAllElements('text').toList()) {
    String attribute(String name, String fallback) {
      XmlElement? node = text;
      while (node != null) {
        final value = node.getAttribute(name);
        if (value != null) return value;
        node = node.parentElement;
      }
      return fallback;
    }

    final size = double.parse(attribute('font-size', '16'));
    final fill = attribute('fill', '#171813');
    final color = fill.startsWith('#')
        ? Color(int.parse('ff${fill.substring(1)}', radix: 16))
        : const Color(0xffffdf84);
    final rtl = attribute('direction', 'ltr') == 'rtl';
    final painter = TextPainter(
      text: TextSpan(
        text: text.innerText,
        style: TextStyle(
          fontSize: size,
          color: color,
          fontFamily: attribute('font-family', 'Arial').split(',').first,
          fontWeight: int.parse(attribute('font-weight', '400')) >= 600
              ? FontWeight.w700
              : FontWeight.w400,
          letterSpacing: double.tryParse(attribute('letter-spacing', '0')) ?? 0,
        ),
      ),
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
    )..layout();
    // Keep long VINs, model names and prices inside their table cells.
    final maxWidth = switch (text.getAttribute('id')) {
      'field-title' ||
      'field-vin' ||
      'field-price' ||
      'field-color' ||
      'field-year' => 280.0,
      'main-number' => 305.0,
      _ => painter.width,
    };
    final scale = math.min(1.0, maxWidth / math.max(1, painter.width));
    final width = math.max(1.0, painter.width * scale);
    final height = math.max(1.0, painter.height * scale);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..scale(3 * scale);
    painter.paint(canvas, Offset.zero);
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (width * 3).ceil(),
      (height * 3).ceil(),
    );
    try {
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final anchor = attribute('text-anchor', 'start');
      var x = double.parse(attribute('x', '0'));
      if (anchor == 'middle') {
        x -= width / 2;
      } else if ((anchor == 'end' && !rtl) || (anchor == 'start' && rtl)) {
        x -= width;
      }
      final y =
          double.parse(attribute('y', '0')) -
          painter.computeDistanceToActualBaseline(TextBaseline.alphabetic) *
              scale;
      final replacement = XmlElement(XmlName.parts('image'), [
        XmlAttribute(XmlName.parts('x'), '$x'),
        XmlAttribute(XmlName.parts('y'), '$y'),
        XmlAttribute(XmlName.parts('width'), '$width'),
        XmlAttribute(XmlName.parts('height'), '$height'),
        XmlAttribute(
          XmlName.parts('href'),
          'data:image/png;base64,${base64Encode(png.buffer.asUint8List())}',
        ),
        if (text.getAttribute('transform') case final String transform)
          XmlAttribute(XmlName.parts('transform'), transform),
      ]);
      text.replace(replacement);
    } finally {
      image.dispose();
      picture.dispose();
      painter.dispose();
    }
  }
  final info = await vg.loadPicture(
    SvgStringLoader(document.toXmlString()),
    null,
  );
  try {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder)
      ..scale(2)
      ..drawPicture(info.picture);
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(2218, 2836);
      try {
        final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        return data.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
    }
  } finally {
    info.picture.dispose();
  }
}

/// Fit one complete label on each sheet, using the printer's page dimensions.
Future<Uint8List> buildVehicleLabelPdf(
  List<Uint8List> labels,
  PdfPageFormat format,
) async {
  final pdf = PdfDocument();
  for (final bytes in labels) {
    final page = PdfPage(pdf, pageFormat: format);
    final image = PdfImage.file(pdf, bytes: bytes);
    final availableWidth = format.availableWidth;
    final availableHeight = format.availableHeight;
    final scale = math.min(
      availableWidth / image.width,
      availableHeight / image.height,
    );
    final width = image.width * scale;
    final height = image.height * scale;
    page.getGraphics().drawImage(
      image,
      format.marginLeft + (availableWidth - width) / 2,
      format.marginBottom + (availableHeight - height) / 2,
      width,
      height,
    );
  }
  return pdf.save();
}
