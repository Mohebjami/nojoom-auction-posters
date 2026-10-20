import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:vehicle_poster/batch_poster_export.dart';
import 'package:vehicle_poster/custom_template.dart';
import 'package:vehicle_poster/poster.dart';
import 'package:vehicle_poster/poster_export.dart';
import 'package:vehicle_poster/poster_history.dart';

const _template = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 200">
<image width="320" height="200" href="{{photo0}}"/>
</svg>
''';

class _History extends PosterHistory {
  _History(this.photo);
  final Uint8List photo;

  @override
  Future<PosterDraft> load(int id) async => PosterDraft(
    id: id,
    vehicle: const VehicleDetails(),
    photos: [photo],
    templateSvg: _template,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Uint8List photo() {
    final random = Random(42);
    final image = img.Image(width: 320, height: 200);
    for (final pixel in image) {
      pixel
        ..r = random.nextInt(256)
        ..g = random.nextInt(256)
        ..b = random.nextInt(256);
    }
    return img.encodePng(image);
  }

  test('PDF JPEG compression reduces size and retains image dimensions', () {
    final png = photo();
    final compressed = encodePosterPdfJpg(png);
    expect(compressed.length, lessThan(encodePosterJpg(png).length * 0.8));
    final decoded = img.decodeJpg(compressed)!;
    expect(decoded.width, 320);
    expect(decoded.height, 200);
  });

  test('PDF JPEG compression flattens transparency onto white', () {
    final image = img.Image(width: 16, height: 16, numChannels: 4);
    img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));
    final decoded = img.decodeJpg(encodePosterPdfJpg(img.encodePng(image)))!;
    final pixel = decoded.getPixel(8, 8);
    expect(pixel.r, greaterThanOrEqualTo(250));
    expect(pixel.g, greaterThanOrEqualTo(250));
    expect(pixel.b, greaterThanOrEqualTo(250));
  });

  test(
    'batch PDF embeds compressed pages while ZIP retains JPG quality',
    () async {
      final png = photo();
      final poster = await CustomPosterTemplate.parse(
        'Test',
        _template,
      ).build(const VehicleDetails(), [png], Uint8List(0));
      final expectedPdfImage = encodePosterPdfJpg(poster.previewImage!);
      final expectedZipImage = encodePosterJpg(poster.previewImage!);
      final history = _History(png);
      final pdf = await generateBatchPosters(
        history: history,
        ids: [1, 2],
        format: BatchPosterFormat.pdf,
      );
      final content = latin1.decode(pdf.bytes);
      expect(content, startsWith('%PDF-'));
      expect(content, contains(latin1.decode(expectedPdfImage)));
      expect(content, isNot(contains(latin1.decode(expectedZipImage))));
      expect(RegExp(r'/Type\s*/Page\b').allMatches(content), hasLength(2));
      expect(content, matches(RegExp(r'/MediaBox\s*\[0 0 320 200\]')));

      final zip = await generateBatchPosters(
        history: history,
        ids: [1],
        format: BatchPosterFormat.jpgZip,
      );
      final jpg = ZipDecoder().decodeBytes(zip.bytes).files.single.content;
      expect(jpg, orderedEquals(expectedZipImage));
    },
  );
}
