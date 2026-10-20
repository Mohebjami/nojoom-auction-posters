import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:vehicle_poster/vehicle_label_print.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'renders label artwork and text and fits one label per printed page',
    () async {
      final template = await rootBundle.loadString('assets/vehicles_label.svg');
      final png = await renderVehicleLabel(template);
      final image = img.decodePng(png)!;
      expect(image.width, 2218);
      expect(image.height, 2836);
      // The dark number panel and pale paper survive SVG rasterization.
      expect(image.getPixel(1500, 200).r, lessThan(100));
      expect(image.getPixel(60, 60).r, greaterThan(180));
      for (final format in [PdfPageFormat.a4, PdfPageFormat.letter.landscape]) {
        final pdf = latin1.decode(
          await buildVehicleLabelPdf([png, png], format),
        );
        expect(pdf, startsWith('%PDF-'));
        expect(RegExp(r'/Type\s*/Page\b').allMatches(pdf), hasLength(2));
        expect(pdf, contains('/Count 2'));
      }
    },
  );
}
