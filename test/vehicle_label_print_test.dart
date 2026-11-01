import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:vehicle_poster/vehicle_label_print.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'renders label artwork and fills one A4 sheet per label regardless of printer margins',
    () async {
      final template = await rootBundle.loadString('assets/vehicles_label.svg');
      final png = await renderVehicleLabel(template);
      final image = img.decodePng(png)!;
      expect(image.width, 2218);
      expect(image.height, 2836);
      // The dark number panel and pale paper survive SVG rasterization.
      expect(image.getPixel(1500, 200).r, lessThan(100));
      expect(image.getPixel(60, 60).r, greaterThan(180));
      for (final format in [
        PdfPageFormat.a4,
        PdfPageFormat.letter.landscape,
        PdfPageFormat.a4.copyWith(
          marginLeft: 50,
          marginRight: 50,
          marginTop: 60,
          marginBottom: 60,
        ),
      ]) {
        final pdf = latin1.decode(
          await buildVehicleLabelPdf([png, png], format),
        );
        expect(pdf, startsWith('%PDF-'));
        expect(RegExp(r'/Type\s*/Page\b').allMatches(pdf), hasLength(2));
        expect(pdf, contains('/Count 2'));
        final boxes = RegExp(r'/MediaBox\s*\[([^\]]+)\]').allMatches(pdf);
        expect(boxes, hasLength(2));
        for (final box in boxes) {
          final dimensions = box
              .group(1)!
              .trim()
              .split(RegExp(r'\s+'))
              .map(double.parse)
              .toList();
          expect(dimensions[0], 0);
          expect(dimensions[1], 0);
          expect(dimensions[2], closeTo(PdfPageFormat.a4.width, .01));
          expect(dimensions[3], closeTo(PdfPageFormat.a4.height, .01));
        }
      }
    },
  );
}
