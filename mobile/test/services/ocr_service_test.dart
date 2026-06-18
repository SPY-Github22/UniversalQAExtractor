import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_qa_extractor/services/ocr_service.dart';
import 'package:image/image.dart' as img;

void main() {
  late MockOcrService ocrService;

  setUp(() {
    ocrService = MockOcrService();
  });

  test('TC-T1-F3-01: OCR Single Line Extraction', () async {
    ocrService.stubbedOutput = "Q1: What is Flutter?";
    final result = await ocrService.recognizeText(Uint8List.fromList([1, 2, 3]));
    expect(result, "Q1: What is Flutter?");
  });

  test('TC-T1-F3-02: OCR Empty Image Handling', () async {
    ocrService.stubbedOutput = "";
    final result = await ocrService.recognizeText(Uint8List.fromList([]));
    expect(result, "");
  });

  test('TC-T1-F3-03: OCR Multi-line Sorting', () async {
    ocrService.stubbedOutput = "Line 1\nLine 2\nLine 3";
    final result = await ocrService.recognizeText(Uint8List.fromList([1, 2, 3]));
    expect(result, "Line 1\nLine 2\nLine 3");
  });

  test('TC-T1-F3-04: OCR Noise Filtering', () async {
    ocrService.stubbedOutput = "Q1: What is Flutter?☀☠★";
    final result = await ocrService.recognizeText(Uint8List.fromList([1, 2, 3]));
    expect(result, "Q1: What is Flutter?");
  });

  test('TC-T1-F3-05: OCR Region of Interest (ROI)', () async {
    ocrService.stubbedOutput = "Select me";
    final roi = const Rect.fromLTWH(0, 0, 100, 100);
    final result = await ocrService.recognizeText(Uint8List.fromList([1, 2, 3]), roi: roi);
    expect(result, contains("Select me"));
    expect(result, contains("[ROI Cropped]"));
  });

  test('TC-T2-F3-01: Extremely Low Resolution Frame', () async {
    ocrService.stubbedOutput = "Too small to recognize";
    final tinyImageBytes = Uint8List.fromList([1, 2, 3, 4, 5]); // Length <= 10
    final result = await ocrService.recognizeText(tinyImageBytes);
    expect(result, "");
  });

  test('TC-T2-F3-02: Out of Memory (OOM)', () async {
    ocrService.shouldThrowOom = true;
    expect(
      ocrService.recognizeText(Uint8List.fromList([1, 2, 3])),
      throwsA(isA<OcrOomException>().having((e) => e.message, 'message', contains('Out of Memory'))),
    );
  });

  test('TC-T2-F3-03: Over-Dense Text Input', () async {
    final denseText = "A" * 6000;
    ocrService.stubbedOutput = denseText;
    final result = await ocrService.recognizeText(Uint8List.fromList([1, 2, 3]));
    expect(result.length, 5000); // Truncated past limit
  });

  test('TC-T2-F3-04: Unsupported Image Format', () async {
    final invalidBytes = Uint8List.fromList([0x99, 0x99]);
    expect(
      ocrService.recognizeText(invalidBytes),
      throwsA(isA<UnsupportedImageFormatException>()),
    );
  });

  test('TC-T2-F3-05: OCR Engine Model Not Ready', () async {
    ocrService.shouldThrowModelNotReady = true;
    expect(
      ocrService.recognizeText(Uint8List.fromList([1, 2, 3])),
      throwsA(isA<ModelNotReadyException>()),
    );
  });

  // Tests for concrete MlKitOcrService
  test('MlKitOcrService throws UnsupportedImageFormatException for empty input', () async {
    final service = MlKitOcrService();
    expect(
      service.recognizeText(Uint8List(0)),
      throwsA(isA<UnsupportedImageFormatException>()),
    );
    service.dispose();
  });

  test('MlKitOcrService throws UnsupportedImageFormatException for invalid bytes', () async {
    final service = MlKitOcrService();
    final invalidBytes = Uint8List.fromList([0x99, 0x99]);
    expect(
      service.recognizeText(invalidBytes),
      throwsA(isA<UnsupportedImageFormatException>()),
    );
    service.dispose();
  });

  test('MlKitOcrService accepts valid PNG and proceeds', () async {
    final service = MlKitOcrService();
    final image = img.Image(width: 5, height: 5);
    final pngBytes = Uint8List.fromList(img.encodePng(image));
    expect(
      () => service.recognizeText(pngBytes),
      throwsA(isNot(isA<UnsupportedImageFormatException>())),
    );
    service.dispose();
  });

  test('MlKitOcrService accepts valid JPEG and proceeds', () async {
    final service = MlKitOcrService();
    final validJpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00]);
    expect(
      () => service.recognizeText(validJpeg),
      throwsA(isNot(isA<UnsupportedImageFormatException>())),
    );
    service.dispose();
  });

  test('MlKitOcrService accepts valid GIF and proceeds', () async {
    final service = MlKitOcrService();
    final validGif = Uint8List.fromList([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00]);
    expect(
      () => service.recognizeText(validGif),
      throwsA(isNot(isA<UnsupportedImageFormatException>())),
    );
    service.dispose();
  });

  test('MlKitOcrService accepts valid BMP and proceeds', () async {
    final service = MlKitOcrService();
    final validBmp = Uint8List.fromList([0x42, 0x4D, 0x3E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);
    expect(
      () => service.recognizeText(validBmp),
      throwsA(isNot(isA<UnsupportedImageFormatException>())),
    );
    service.dispose();
  });

  test('MlKitOcrService crops image when ROI is provided', () async {
    final service = MlKitOcrService();
    final image = img.Image(width: 10, height: 10);
    final pngBytes = Uint8List.fromList(img.encodePng(image));
    final roi = const Rect.fromLTWH(2, 2, 5, 5);
    expect(
      () => service.recognizeText(pngBytes, roi: roi),
      throwsA(isNot(isA<UnsupportedImageFormatException>())),
    );
    service.dispose();
  });
}
