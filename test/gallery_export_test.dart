import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:vehicle_poster/gallery_export.dart';
import 'package:vehicle_poster/poster_export.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('gal');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'Gallery requests access and receives a real JPG without a double extension',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'hasAccess') return false;
        if (call.method == 'requestAccess') return true;
        return null;
      });
      final bytes = encodePosterJpg(
        img.encodePng(img.Image(width: 10, height: 20)),
      );
      await ensureGalleryAccess();
      await saveJpgToGallery(bytes, 'vehicle-9.jpg');
      expect(calls.first.method, 'hasAccess');
      expect(calls.any((call) => call.method == 'requestAccess'), isTrue);
      final write = calls.singleWhere((call) => call.method == 'putImageBytes');
      expect(write.arguments['name'], 'vehicle-9');
      expect(write.arguments['bytes'], bytes);
      expect(img.decodeJpg(write.arguments['bytes'])!.height, 20);
    },
  );

  test(
    'Denied gallery permission stops the save with a useful error',
    () async {
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return false;
      });
      await expectLater(
        ensureGalleryAccess(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('settings'),
          ),
        ),
      );
      expect(calls, ['hasAccess', 'requestAccess']);
    },
  );

  test(
    'Gallery storage failure is propagated instead of reporting success',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'requestAccess') return true;
        throw PlatformException(code: 'NOT_ENOUGH_SPACE');
      });
      await expectLater(
        saveJpgToGallery(Uint8List(0), 'poster.jpg'),
        throwsA(isA<GalException>()),
      );
    },
  );
}
