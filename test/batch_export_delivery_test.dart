import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_poster/batch_export_delivery.dart';
import 'package:vehicle_poster/batch_poster_export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const fileChannel = MethodChannel('plugins.flutter.io/file_selector');
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
  const origin = Rect.fromLTWH(10, 20, 50, 40);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;

  BatchPosterExport export({bool pdf = true, int marker = 1}) =>
      BatchPosterExport(
        bytes: Uint8List.fromList([marker, 2, 3, 4]),
        fileName: pdf ? 'vehicle-posters.pdf' : 'vehicle-posters.zip',
        mimeType: pdf ? 'application/pdf' : 'application/zip',
        count: 2,
      );

  setUp(() {
    directory = Directory.systemTemp.createTempSync('batch-delivery-test-');
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    messenger.setMockMethodCallHandler(pathChannel, (call) async {
      expect(call.method, 'getTemporaryDirectory');
      return directory.path;
    });
  });

  tearDown(() {
    for (final channel in [fileChannel, pathChannel, shareChannel]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    debugDefaultTargetPlatformOverride = null;
    directory.deleteSync(recursive: true);
  });

  for (final pdf in [true, false]) {
    test(
      'desktop saves ${pdf ? 'PDF' : 'ZIP'} with its correct file type',
      () async {
        final batch = export(pdf: pdf);
        final output = File('${directory.path}/${batch.fileName}');
        messenger.setMockMethodCallHandler(fileChannel, (call) async {
          expect(call.method, 'getSavePath');
          expect(call.arguments['suggestedName'], batch.fileName);
          final filter = (call.arguments['acceptedTypeGroups'] as List).single;
          expect(filter['extensions'], [pdf ? 'pdf' : 'zip']);
          expect(filter['mimeTypes'], [batch.mimeType]);
          expect(filter['uniformTypeIdentifiers'], [
            pdf ? 'com.adobe.pdf' : 'public.zip-archive',
          ]);
          return output.path;
        });

        expect(
          await saveBatchPosterExport(batch, sharePositionOrigin: origin),
          pdf ? 'PDF saved.' : 'JPG ZIP saved.',
        );
        expect(await output.readAsBytes(), batch.bytes);
      },
    );
  }

  test(
    'cancelling the desktop save writes no files or success message',
    () async {
      messenger.setMockMethodCallHandler(fileChannel, (call) async => null);

      expect(
        await saveBatchPosterExport(export(), sharePositionOrigin: origin),
        isNull,
      );
      expect(directory.listSync(), isEmpty);
    },
  );

  test(
    'desktop write failure is propagated instead of reporting success',
    () async {
      messenger.setMockMethodCallHandler(
        fileChannel,
        (call) async => '${directory.path}/missing/posters.pdf',
      );

      await expectLater(
        saveBatchPosterExport(export(), sharePositionOrigin: origin),
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  test(
    'mobile keeps distinct readable exports and anchors the share sheet',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final sharedPaths = <String>[];
      messenger.setMockMethodCallHandler(shareChannel, (call) async {
        expect(call.method, 'share');
        expect(call.arguments['mimeTypes'], ['application/pdf']);
        expect(call.arguments['originX'], origin.left);
        expect(call.arguments['originY'], origin.top);
        expect(call.arguments['originWidth'], origin.width);
        expect(call.arguments['originHeight'], origin.height);
        sharedPaths.add((call.arguments['paths'] as List).single as String);
        expect(File(sharedPaths.last).existsSync(), isTrue);
        return 'com.apple.UIKit.activity.SaveToFiles';
      });

      final first = export(marker: 1);
      final second = export(marker: 9);
      expect(
        await saveBatchPosterExport(first, sharePositionOrigin: origin),
        'PDF shared.',
      );
      expect(
        await saveBatchPosterExport(second, sharePositionOrigin: origin),
        'PDF shared.',
      );
      expect(sharedPaths.toSet(), hasLength(2));
      expect(await File(sharedPaths.first).readAsBytes(), first.bytes);
      expect(await File(sharedPaths.last).readAsBytes(), second.bytes);
      expect(
        sharedPaths.every((path) => path.endsWith('/${first.fileName}')),
        isTrue,
      );
    },
  );

  for (final result in ['', 'dev.fluttercommunity.plus/share/unavailable']) {
    test(
      'mobile does not claim success for ${result.isEmpty ? 'dismissed' : 'unconfirmed'} sharing',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        messenger.setMockMethodCallHandler(
          shareChannel,
          (call) async => result,
        );

        expect(
          await saveBatchPosterExport(
            export(pdf: false),
            sharePositionOrigin: origin,
          ),
          isNull,
        );
      },
    );
  }
}
