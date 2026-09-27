import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sembast/sembast_memory.dart';
import 'package:xml/xml.dart';
import 'package:vehicle_poster/custom_template.dart';
import 'package:vehicle_poster/main.dart';
import 'package:vehicle_poster/poster.dart';
import 'package:vehicle_poster/poster_export.dart';
import 'package:vehicle_poster/poster_history.dart';
import 'package:vehicle_poster/studio_ui.dart';
import 'history_test.dart' show settleStorage;

const source = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 300 200">
<rect width="300" height="200" fill="#ffffff"/>
<text x="10" y="25" font-size="20" data-max-width="280">{{title}}</text>
<image x="0" y="50" width="150" height="150" href="{{photo0}}"/>
<image x="150" y="50" width="150" height="150" href="{{photo1}}"/>
</svg>''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Compression preserves photo pixels, transparency, and vector geometry', () {
    final photo = img.Image(width: 100, height: 80, numChannels: 4);
    img.fillRect(
      photo,
      x1: 20,
      y1: 20,
      x2: 90,
      y2: 70,
      color: img.ColorRgba8(220, 40, 70, 128),
    );
    final uri =
        'data:image/png;base64,${base64Encode(img.encodePng(photo, level: 0))}';
    final svg =
        '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 300 200"><path d="M0 0L20 40Z"/><image x="20" y="30" width="100" height="80" href="$uri" xlink:href="$uri"/></svg>';
    final result = compressPosterSvg(svg);
    expect(result.length, lessThan(utf8.encode(svg).length ~/ 2));
    final doc = XmlDocument.parse(utf8.decode(result));
    final image = doc.findAllElements('image').single;
    expect(image.getAttribute('x'), '20');
    expect(image.getAttribute('height'), '80');
    expect(image.attributes.where((a) => a.name.local == 'href'), hasLength(1));
    final decoded = img.decodePng(
      base64Decode(image.getAttribute('href')!.split(',').last),
    )!;
    expect(decoded.getBytes(), orderedEquals(photo.getBytes()));
    expect(doc.findAllElements('path').single.getAttribute('d'), 'M0 0L20 40Z');
    const tiny = '<svg xmlns="http://www.w3.org/2000/svg"/>';
    expect(
      compressPosterSvg(tiny).length,
      lessThanOrEqualTo(utf8.encode(tiny).length),
    );
  });
  test(
    'Template escapes details, fits long titles and omits missing photos',
    () {
      final template = CustomPosterTemplate.parse('Custom', source);
      final result = template.populate(
        const VehicleDetails(
          title: 'A & B <TRUCK> WITH A VERY LONG VEHICLE TITLE',
        ),
        [],
        Uint8List(0),
      );
      final doc = XmlDocument.parse(result);
      final text = doc.findAllElements('text').single;
      expect(text.innerText, 'A & B <TRUCK> WITH A VERY LONG VEHICLE TITLE');
      expect(double.parse(text.getAttribute('font-size')!), lessThan(20));
      expect(doc.findAllElements('image'), isEmpty);
      expect(result, isNot(contains('{{')));
    },
  );
  test('Invalid templates and external content are rejected', () {
    for (final invalid in [
      '<svg viewBox="0 0 300 200"><text>No placeholders</text></svg>',
      source.replaceAll('{{title}}', '{{unknown}}'),
      source.replaceAll('300 200', '99999 99999'),
      source.replaceAll('{{photo0}}', 'https://example.com/car.png'),
      source.replaceAll('{{photo0}}', '#{{title}}'),
      source.replaceAll('</svg>', '<script>alert(1)</script></svg>'),
      source.replaceAll('fill="#ffffff"', 'onload="alert(1)"'),
      source.replaceAll(
        'fill="#ffffff"',
        'fill="url(https://example.com/pattern)"',
      ),
      source.replaceAll('x="10"', 'x="{{title}}"'),
    ]) {
      expect(
        () => CustomPosterTemplate.parse('Bad', invalid),
        throwsFormatException,
      );
    }
  });
  testWidgets('Custom preview uses template dimensions and supplied photos', (
    tester,
  ) async {
    final photo = img.Image(width: 20, height: 20);
    img.fill(photo, color: img.ColorRgb8(230, 20, 30));
    final template = CustomPosterTemplate.parse('Custom', source);
    final poster = (await tester.runAsync(
      () => template.build(const VehicleDetails(title: 'TEST'), [
        img.encodePng(photo),
      ], Uint8List(0)),
    ))!;
    final preview = img.decodePng(poster.previewImage!)!;
    expect(preview.width, 300);
    expect(preview.height, 200);
    expect(preview.getPixel(50, 100).r, 230);
    expect(preview.getPixel(50, 100).g, 20);
    expect(preview.getPixel(250, 100).r, 255);
    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        home: PreviewScreen(
          designSvg: poster.designSvg,
          exportSvg: poster.exportSvg,
          number: '',
          photos: poster.photos,
          logo: poster.logo,
          previewImage: poster.previewImage,
          canvasSize: poster.canvasSize,
        ),
      ),
    );
    await tester.runAsync(
      () => precacheImage(
        MemoryImage(poster.previewImage!),
        tester.element(find.byType(PreviewScreen)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('300 × 200 px'), findsOneWidget);
    expect(find.text('Share SVG').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Switching templates preserves data and history restores the saved design',
    (tester) async {
      final db = (await tester.runAsync(
        () => databaseFactoryMemory.openDatabase('template-roundtrip'),
      ))!;
      addTearDown(db.close);
      final history = PosterHistory(openDatabase: () async => db);
      await tester.pumpWidget(
        MaterialApp(
          theme: studioTheme(),
          home: EditorScreen(history: history),
        ),
      );
      final title = tester
          .widget<TextField>(find.byType(TextField).first)
          .controller!;
      title.text = 'MY TOYOTA';
      await tester.ensureVisible(find.byTooltip('Change template'));
      await tester.tap(find.byTooltip('Change template'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clean showroom'));
      await tester.pumpAndSettle();
      expect(title.text, 'MY TOYOTA');
      await tester.tap(find.text('Save draft'));
      await settleStorage(tester);
      final entries = (await tester.runAsync(history.list))!;
      final draft = (await tester.runAsync(
        () => history.load(entries.single.id),
      ))!;
      expect(draft.templateName, 'Clean showroom');
      expect(draft.templateSvg, contains('{{photo0}}'));
      await tester.ensureVisible(find.byTooltip('Change template'));
      await tester.tap(find.byTooltip('Change template'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Original artwork'));
      await tester.pumpAndSettle();
      expect(title.text, 'MY TOYOTA');
      // Reopen from a fresh editor, as on a subsequent application launch.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          theme: studioTheme(),
          home: EditorScreen(history: history),
        ),
      );
      await tester.tap(find.byTooltip('History'));
      await settleStorage(tester);
      await tester.scrollUntilVisible(
        find.text('MY TOYOTA'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('MY TOYOTA'));
      await settleStorage(tester);
      expect(find.text('Clean showroom'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'MY TOYOTA',
      );
      expect(tester.takeException(), isNull);
    },
  );
  test('Older drafts without template metadata still load', () async {
    final db = await databaseFactoryMemory.openDatabase('old-template-draft');
    addTearDown(db.close);
    final history = PosterHistory(openDatabase: () async => db);
    final id = await history.save(
      const VehicleDetails(title: 'Old draft'),
      List.filled(4, null),
    );
    final store = intMapStoreFactory.store('entries');
    final record = Map<String, Object?>.from((await store.record(id).get(db))!);
    record.remove('templateSvg');
    record.remove('templateName');
    await store.record(id).put(db, record);
    final draft = await history.load(id);
    expect(draft.templateSvg, isNull);
    expect(draft.vehicle.title, 'Old draft');
  });
}
