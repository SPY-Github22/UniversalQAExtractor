import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_qa_extractor/services/screen_capture_service.dart';
import 'package:universal_qa_extractor/services/ocr_service.dart';
import 'package:image/image.dart' as img;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScreenCaptureService Adversarial and Stress Tests', () {
    late ScreenCaptureService service;
    late MethodChannel methodChannel;
    late List<MethodCall> methodCallLog;
    late dynamic captureResultMock; // dynamic to test type mismatch
    late bool isCapturingMock;

    setUp(() {
      service = ScreenCaptureService();
      methodChannel = const MethodChannel('com.universalqaextractor.mobile/screen_capture');
      methodCallLog = <MethodCall>[];
      captureResultMock = true;
      isCapturingMock = false;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (MethodCall methodCall) async {
        methodCallLog.add(methodCall);
        switch (methodCall.method) {
          case 'startCapture':
            if (captureResultMock is Exception) {
              throw captureResultMock;
            }
            if (captureResultMock == true) {
              isCapturingMock = true;
            }
            return captureResultMock;
          case 'stopCapture':
            if (captureResultMock is Exception) {
              throw captureResultMock;
            }
            if (captureResultMock == true) {
              isCapturingMock = false;
            }
            return captureResultMock;
          case 'isCapturing':
            return isCapturingMock;
          default:
            return null;
        }
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, null);
      service.dispose();
    });

    test('SC-ADV-01: Configuration boundaries - Overflowing 32-bit max integer values', () async {
      // Dart integers are 64-bit, but native layer might parse as 32-bit signed integers.
      // Maximum signed 32-bit int: 2147483647
      final largeInt = 999999999999;
      
      // Since validateConfig in screen_capture_service.dart only checks <=0 and <0:
      // It will allow large values. We verify that startCapture propagates these values to the MethodChannel.
      final result = await service.startCapture(width: largeInt, height: largeInt, x: largeInt, y: largeInt);
      expect(result, isTrue);
      expect(methodCallLog.last.arguments['width'], largeInt);
      expect(methodCallLog.last.arguments['height'], largeInt);
      expect(methodCallLog.last.arguments['x'], largeInt);
      expect(methodCallLog.last.arguments['y'], largeInt);
    });

    test('SC-ADV-02: Platform channel returning type mismatch (int instead of bool)', () async {
      captureResultMock = 1; // Native side returns integer instead of boolean
      
      // Dart expects Future<bool>, and the implementation does:
      // final bool? result = await _methodChannel.invokeMethod<bool>('startCapture', ...);
      // Since native returns dynamic (int), this will throw a TypeError in Flutter's invokeMethod.
      expect(
        service.startCapture(),
        throwsA(isA<TypeError>()),
      );
      expect(service.isCapturing, isFalse);
    });

    test('SC-ADV-03: Platform channel returning null', () async {
      captureResultMock = null; // Native side returns null
      
      final result = await service.startCapture();
      // Implementation: if (result == true) { ... return true; } return false;
      // Since result is null, it should return false and not crash or throw.
      expect(result, isFalse);
      expect(service.isCapturing, isFalse);
    });

    test('SC-ADV-04: Rapid Start-Stop cycle stress test', () async {
      final List<Future<bool>> futures = [];
      // Rapidly trigger start and stop multiple times in the same microtask loop
      for (int i = 0; i < 50; i++) {
        futures.add(service.startCapture());
        futures.add(service.stopCapture());
      }
      
      final results = await Future.wait(futures);
      expect(results.length, 100);
      // The state machine should not crash, and must end up in a consistent state
      expect(service.isCapturing, isFalse);
    });

    test('SC-ADV-05: stopCapture fails (returns false)', () async {
      await service.startCapture();
      expect(service.isCapturing, isTrue);

      captureResultMock = false; // Native side fails to stop and returns false
      final result = await service.stopCapture();
      expect(result, isFalse);
      
      // Let's see if _isCapturing remains true because stop failed
      expect(service.isCapturing, isTrue);
    });

    test('SC-ADV-06: Non-Uint8List frames received on frame_stream EventChannel', () async {
      final List<Uint8List> receivedFrames = [];
      final subscription = service.frameStream.listen((frame) {
        receivedFrames.add(frame);
      });

      await service.startCapture();

      // Simulate native side pushing a String instead of Uint8List
      const StandardMethodCodec codec = StandardMethodCodec();
      final ByteData message = codec.encodeSuccessEnvelope("Not a Uint8List frame!");
      
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        'com.universalqaextractor.mobile/frame_stream',
        message,
        (ByteData? reply) {},
      );

      await Future<void>.delayed(Duration.zero);

      // It should be silently ignored (since event is checked: if (event is Uint8List))
      expect(receivedFrames, isEmpty);

      await subscription.cancel();
    });
  });

  group('OcrService / MlKitOcrService / MockOcrService Adversarial Tests', () {
    late MockOcrService mockOcrService;

    setUp(() {
      mockOcrService = MockOcrService();
    });

    test('OCR-ADV-01: ROI Coordinates out of bounds of the actual image', () async {
      final service = MlKitOcrService();
      
      // 5x5 image
      final image = img.Image(width: 5, height: 5);
      final pngBytes = Uint8List.fromList(img.encodePng(image));
      
      // Rect out of bounds: left 10, top 10 (image size is only 5x5)
      final outOfBoundsRoi = const Rect.fromLTWH(10, 10, 20, 20);
      
      expect(
        () => service.recognizeText(pngBytes, roi: outOfBoundsRoi),
        throwsA(isNot(isA<UnsupportedImageFormatException>())),
      );
      service.dispose();
    });

    test('OCR-ADV-02: Negative ROI Coordinates', () async {
      final service = MlKitOcrService();
      final image = img.Image(width: 5, height: 5);
      final pngBytes = Uint8List.fromList(img.encodePng(image));
      
      // Rect with negative coordinates
      final negativeRoi = const Rect.fromLTWH(-5, -5, 10, 10);
      
      expect(
        () => service.recognizeText(pngBytes, roi: negativeRoi),
        throwsA(isNot(isA<UnsupportedImageFormatException>())),
      );
      service.dispose();
    });

    test('OCR-ADV-03: Truncated Image Bytes starting with valid PNG header', () async {
      final service = MlKitOcrService();
      
      // Truncated image bytes containing ONLY the 4 PNG magic bytes
      final truncatedPng = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
      
      expect(
        () => service.recognizeText(truncatedPng),
        throwsA(isNot(isA<UnsupportedImageFormatException>())),
      );
      service.dispose();
    });

    test('OCR-ADV-04: MockOcrService OOM Exception mapping', () async {
      mockOcrService.shouldThrowOom = true;
      expect(
        mockOcrService.recognizeText(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<OcrOomException>()),
      );
    });

    test('OCR-ADV-05: MockOcrService Model Not Ready Exception mapping', () async {
      mockOcrService.shouldThrowModelNotReady = true;
      expect(
        mockOcrService.recognizeText(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<ModelNotReadyException>()),
      );
    });

    test('OCR-ADV-06: MockOcrService Unsupported Format Exception mapping', () async {
      mockOcrService.shouldThrowUnsupportedFormat = true;
      expect(
        mockOcrService.recognizeText(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<UnsupportedImageFormatException>()),
      );
    });

    test('OCR-ADV-07: Concurrent OCR processing requests on concrete MlKitOcrService', () async {
      final service = MlKitOcrService();
      final image = img.Image(width: 5, height: 5);
      final pngBytes = Uint8List.fromList(img.encodePng(image));

      final List<Future<String>> futures = [];
      for (int i = 0; i < 10; i++) {
        futures.add(service.recognizeText(pngBytes));
      }

      final results = await Future.wait(
        futures.map((f) => f.catchError((Object e) => e.toString())),
      );

      expect(results.length, 10);
      for (final res in results) {
        expect(res, contains("native failure"));
      }

      service.dispose();
    });
  });
}
