import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vehicle_poster/backup_delivery.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
  const origin = Rect.fromLTWH(10, 20, 50, 40);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('backup-share-test-');
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    messenger.setMockMethodCallHandler(
      pathChannel,
      (call) async => directory.path,
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(pathChannel, null);
    messenger.setMockMethodCallHandler(shareChannel, null);
    debugDefaultTargetPlatformOverride = null;
    directory.deleteSync(recursive: true);
  });

  test(
    'mobile shares complete ZIP bytes from unique files and anchors the share sheet',
    () async {
      final sharedPaths = <String>[];
      messenger.setMockMethodCallHandler(shareChannel, (call) async {
        expect(call.method, 'share');
        expect(call.arguments['mimeTypes'], ['application/zip']);
        expect(call.arguments['originX'], origin.left);
        expect(call.arguments['originY'], origin.top);
        expect(call.arguments['originWidth'], origin.width);
        expect(call.arguments['originHeight'], origin.height);
        sharedPaths.add((call.arguments['paths'] as List).single as String);
        return 'com.apple.UIKit.activity.SaveToFiles';
      });
      for (final bytes in [
        Uint8List.fromList([1, 2]),
        Uint8List.fromList([3, 4]),
      ]) {
        expect(
          await savePosterBackup(bytes, sharePositionOrigin: origin),
          'Backup shared.',
        );
        expect(await File(sharedPaths.last).readAsBytes(), bytes);
        expect(sharedPaths.last, endsWith('.zip'));
      }
      expect(sharedPaths.toSet(), hasLength(2));
    },
  );

  for (final response in ['', 'dev.fluttercommunity.plus/share/unavailable']) {
    test(
      'dismissed or unconfirmed mobile sharing does not claim backup success: $response',
      () async {
        messenger.setMockMethodCallHandler(
          shareChannel,
          (call) async => response,
        );
        expect(
          await savePosterBackup(
            Uint8List.fromList([1, 2]),
            sharePositionOrigin: origin,
          ),
          isNull,
        );
      },
    );
  }
}
