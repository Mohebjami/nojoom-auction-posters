import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_poster/main.dart';
import 'package:vehicle_poster/poster.dart';
import 'package:vehicle_poster/poster_export.dart';
import 'package:vehicle_poster/custom_template.dart';
import 'package:vehicle_poster/studio_ui.dart';

List<Uint8List> _referencePhotos(String original) {
  return [0, 1, 2, 4].map((index) {
    final start = original.indexOf('<image id="image${index}_2231_392"');
    final href =
        original.indexOf('xlink:href="', start) + 'xlink:href="'.length;
    final end = original.indexOf('"', href);
    final uri = original.substring(href, end);
    return base64Decode(uri.substring(uri.indexOf(',') + 1));
  }).toList();
}

void _expectLocalReferencesResolve(String svg) {
  final ids = RegExp(
    r'''\bid=["']([^"']+)["']''',
  ).allMatches(svg).map((match) => match.group(1)!).toSet();
  final references = [
    ...RegExp(r'url\(#([^\)]+)\)').allMatches(svg),
    ...RegExp(r'''\bhref=["']#([^"']+)["']''').allMatches(svg),
  ];
  for (final reference in references) {
    expect(
      ids,
      contains(reference.group(1)),
      reason: 'Unresolved SVG reference: ${reference.group(0)}',
    );
  }
}

Iterable<String> _vehicleImages(String svg) {
  return RegExp(r'<image\b[^>]*>')
      .allMatches(svg)
      .map((match) => match.group(0)!)
      .where((image) => image.contains('vehicle-photo-'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const details = VehicleDetails(
    number: '2',
    title: '2010 TOYOTA',
    model: 'COROLLA',
    price: '6000',
    color: 'SILVER',
    vin: 'JTDKN3DU2A0090987',
  );
  late PosterTemplate template;
  late List<Uint8List> photos;

  setUpAll(() async {
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    // Optional local font for readable visual QA artifacts; tests remain portable.
    final fontFile = File('/System/Library/Fonts/Supplemental/Arial.ttf');
    if (fontFile.existsSync()) {
      final loader = FontLoader('Roboto')
        ..addFont(
          Future.value(ByteData.sublistView(fontFile.readAsBytesSync())),
        );
      await loader.load();
    }
    template = await PosterTemplate.load();
    photos = _referencePhotos(
      File('reference/Group 11.svg').readAsStringSync(),
    );
  });

  test('Default text preserves the original vector outlines', () async {
    final poster = await template.build(details, photos);
    for (final outline
        in template.originals.entries
            .where((entry) => entry.key != 'typeColor')
            .map((entry) => entry.value)) {
      expect(poster.designSvg, contains(outline as String));
      expect(poster.exportSvg, contains(outline));
    }
  });

  test(
    'Export embeds the same prepared photo pixels used by the preview',
    () async {
      final poster = await template.build(details, photos);
      final images = _vehicleImages(poster.exportSvg).toList();

      expect(images, hasLength(4));
      for (final image in images) {
        expect(
          RegExp(r'''preserveAspectRatio=["']none["']''').hasMatch(image),
          isTrue,
          reason: 'Prepared photos must fill their explicit frame bounds.',
        );
      }
      for (var index = 0; index < photos.length; index++) {
        expect(poster.exportSvg, contains(base64Encode(poster.photos[index]!)));
        expect(poster.exportSvg, contains('id="vehicle-photo-$index"'));
      }
      _expectLocalReferencesResolve(poster.exportSvg);
    },
  );

  test('Real SVG compression and sample template reuse', () async {
    final poster = await template.build(details, photos);
    final compressed = compressPosterSvg(poster.exportSvg);
    final originalBytes = utf8.encode(poster.exportSvg).length;
    expect(compressed.length, lessThan(originalBytes * .65));
    _expectLocalReferencesResolve(utf8.decode(compressed));
    expect(_vehicleImages(utf8.decode(compressed)), hasLength(4));
    final sample = await CustomPosterTemplate.sample();
    final alternate = await sample.build(details, photos, poster.logo);
    expect(alternate.exportSvg, isNot(contains('{{')));
    expect(alternate.previewImage, isNotEmpty);
    Directory('build/verification').createSync(recursive: true);
    File(
      'build/verification/compressed-poster.svg',
    ).writeAsBytesSync(compressed);
    File(
      'build/verification/clean-showroom.png',
    ).writeAsBytesSync(alternate.previewImage!);
    File('build/verification/svg-size.json').writeAsStringSync(
      jsonEncode({
        'originalBytes': originalBytes,
        'compressedBytes': compressed.length,
        'reductionPercent': (1 - compressed.length / originalBytes) * 100,
      }),
    );
  });

  test(
    'Preview design omits photos while preserving logo and decoration',
    () async {
      final poster = await template.build(details, photos);
      expect(_vehicleImages(poster.designSvg), isEmpty);
      for (final photo in photos) {
        expect(poster.designSvg, isNot(contains(base64Encode(photo))));
      }
      for (final svg in [poster.designSvg, poster.exportSvg]) {
        expect(svg, isNot(contains('<pattern')));
        expect(svg, isNot(contains('image3_2231_392')));
        expect(svg, isNot(contains('{{')));
        expect(svg, isNot(contains('_2231_724')));
        for (final oldPhoto in [0, 1, 2, 4]) {
          expect(svg, isNot(contains('image${oldPhoto}_2231_392')));
          expect(svg, isNot(contains('pattern${oldPhoto}_2231_392')));
        }
        _expectLocalReferencesResolve(svg);
      }
    },
  );

  test(
    'Photo outlines retain the main and thumbnail diagonal corners',
    () async {
      final main = PosterTemplate.photoFrames[0];
      final mainPath = main.clipPath(main.bounds.size);
      expect(mainPath.contains(const Offset(20, 20)), isFalse);
      expect(mainPath.contains(const Offset(20, 280)), isTrue);
      expect(mainPath.contains(const Offset(990, 1090)), isFalse);
      expect(mainPath.contains(const Offset(500, 500)), isTrue);

      final topLeft = PosterTemplate.photoFrames[1];
      final topLeftPath = topLeft.clipPath(topLeft.bounds.size);
      expect(topLeftPath.contains(const Offset(430, 5)), isFalse);
      expect(topLeftPath.contains(const Offset(10, 10)), isTrue);
    },
  );

  test(
    'Custom values replace all editable fields with vector outlines',
    () async {
      final poster = await template.build(
        const VehicleDetails(
          number: '127',
          title: '2024 TOYOTA',
          model: 'LAND CRUISER',
          price: '42500',
          color: 'BLACK',
          vin: 'JTDBR32E720012345',
        ),
        photos,
      );
      for (final svg in [poster.designSvg, poster.exportSvg]) {
        expect(svg, isNot(contains('{{')));
        expect(svg, isNot(contains('<text')));
        expect(svg, contains('viewBox="0 0 1621 1987"'));
        for (final outline in template.originals.values) {
          expect(svg, isNot(contains(outline as String)));
        }
      }
    },
  );

  test('Missing photos and fields remain optional', () async {
    final empty = await template.build(const VehicleDetails(), []);
    expect(empty.exportSvg, contains('id="poster-logo"'));
    expect(empty.logo, isNotEmpty);
    expect(empty.exportSvg, isNot(contains('{{')));
    expect(_vehicleImages(empty.exportSvg), isEmpty);
    _expectLocalReferencesResolve(empty.exportSvg);

    final partial = await template.build(
      const VehicleDetails(model: '4RUNNER'),
      [null, photos[1], null, null],
    );
    expect(_vehicleImages(partial.exportSvg), hasLength(1));
    expect(partial.exportSvg, contains(base64Encode(partial.photos[1]!)));
    expect(partial.exportSvg, isNot(contains(base64Encode(photos[0]))));
    _expectLocalReferencesResolve(partial.exportSvg);
  });

  test(
    'Unsupported optional text does not prevent generating a poster',
    () async {
      final poster = await template.build(
        const VehicleDetails(title: '🚗', model: '4RUNNER'),
        [],
      );
      expect(poster.exportSvg, isNot(contains('{{')));
      expect(poster.exportSvg, isNot(contains('🚗')));
      _expectLocalReferencesResolve(poster.exportSvg);
    },
  );

  test('Fonts contain every allowed character', () async {
    final data = jsonDecode(await rootBundle.loadString('assets/glyphs.json'));
    for (final weight in ['Bold', 'ExtraBold']) {
      for (var character = 32; character < 127; character++) {
        expect(
          data[weight]['glyphs'][String.fromCharCode(character)],
          isNotNull,
        );
      }
    }
  });

  testWidgets('Editor offers four photos and optional vehicle fields', (
    tester,
  ) async {
    await tester.pumpWidget(const VehiclePosterApp());
    expect(find.text('Type / trim'), findsNothing);
    expect(find.byType(TextField), findsNWidgets(6));
    expect(find.text('Main photo'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Bottom-left photo'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Bottom-left photo'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Top-left number'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Top-left number'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Generate poster'),
    );
    expect(button.onPressed, isNotNull);
  });

  test(
    'Prepared main photo keeps centered cover crop and transparent corners',
    () async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 300, 100),
        Paint()..color = Colors.red,
      );
      canvas.drawRect(
        const Rect.fromLTWH(100, 0, 100, 100),
        Paint()..color = Colors.green,
      );
      final picture = recorder.endRecording();
      final source = await picture.toImage(300, 100);
      final bytes = (await source.toByteData(
        format: ui.ImageByteFormat.png,
      ))!.buffer.asUint8List();
      final poster = await template.build(const VehicleDetails(), [bytes]);
      final codec = await ui.instantiateImageCodec(poster.photos.first!);
      final image = (await codec.getNextFrame()).image;
      final rgba = (await image.toByteData())!.buffer.asUint8List();
      expect(image.width, 999);
      expect(image.height, 1097);
      expect(rgba[(20 * image.width + 20) * 4 + 3], 0);
      final center = (548 * image.width + 499) * 4;
      expect(rgba[center], 76);
      expect(rgba[center + 1], 175);
      expect(rgba[center + 2], 80);
      expect(rgba[center + 3], 255);
      expect(poster.exportSvg, contains(base64Encode(poster.photos.first!)));
      image.dispose();
      codec.dispose();
      source.dispose();
      picture.dispose();
    },
  );

  for (final size in [const Size(390, 844), const Size(1280, 900)]) {
    testWidgets('Editor fits ${size.width.toInt()}px viewport', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(key: key, child: const VehiclePosterApp()),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Generate poster').hitTestable(), findsOneWidget);
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory('build/verification').createSync(recursive: true);
        File(
          'build/verification/editor-${size.width.toInt()}.png',
        ).writeAsBytesSync(data!.buffer.asUint8List());
        image.dispose();
      });
    });
  }

  for (final size in [const Size(390, 844), const Size(1440, 1000)]) {
    testWidgets('Preview paints the logo and all photos at ${size.width}', (
      tester,
    ) async {
      final poster = (await tester.runAsync(
        () => template.build(details, photos),
      ))!;
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: studioTheme(),
          home: RepaintBoundary(
            key: key,
            child: PreviewScreen(
              designSvg: poster.designSvg,
              exportSvg: poster.exportSvg,
              number: '2',
              photos: poster.photos,
              logo: poster.logo,
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        for (final bytes in [
          ...poster.photos.whereType<Uint8List>(),
          poster.logo,
        ]) {
          await precacheImage(MemoryImage(bytes), key.currentContext!);
        }
      });
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNWidgets(5));
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory('build/verification').createSync(recursive: true);
        File(
          'build/verification/poster-preview-${size.width.toInt()}.png',
        ).writeAsBytesSync(data!.buffer.asUint8List());
        File(
          'build/verification/poster.svg',
        ).writeAsStringSync(poster.exportSvg);
        image.dispose();
      });
    });
  }
}
