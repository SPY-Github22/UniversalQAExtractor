import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

class UnsupportedImageFormatException implements Exception {
  final String message;
  UnsupportedImageFormatException(this.message);
  @override
  String toString() => "UnsupportedImageFormatException: $message";
}

class ModelNotReadyException implements Exception {
  final String message;
  ModelNotReadyException(this.message);
  @override
  String toString() => "ModelNotReadyException: $message";
}

class OcrOomException implements Exception {
  final String message;
  OcrOomException(this.message);
  @override
  String toString() => "OcrOomException: $message";
}

abstract class OcrService {
  Future<String> recognizeText(Uint8List imageBytes, {Rect? roi});
}

typedef IOcrService = OcrService;

class MlKitOcrService implements OcrService {
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  void _isValidImageHeader(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw UnsupportedImageFormatException("Format invalid");
    }

    // PNG
    if (bytes.length >= 4 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return;
    }

    // JPEG
    if (bytes.length >= 2 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8) {
      return;
    }

    // GIF
    if (bytes.length >= 3 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46) {
      return;
    }

    // BMP
    if (bytes.length >= 2 &&
        bytes[0] == 0x42 &&
        bytes[1] == 0x4D) {
      return;
    }

    throw UnsupportedImageFormatException("Format invalid");
  }

  @override
  Future<String> recognizeText(Uint8List imageBytes, {Rect? roi}) async {
    File? tempFile;
    try {
      _isValidImageHeader(imageBytes);

      Uint8List bytesToProcess = imageBytes;
      if (roi != null) {
        final decoded = img.decodeImage(imageBytes);
        if (decoded != null) {
          final cropped = img.copyCrop(
            decoded,
            x: roi.left.round(),
            y: roi.top.round(),
            width: roi.width.round(),
            height: roi.height.round(),
          );
          bytesToProcess = Uint8List.fromList(img.encodePng(cropped));
        }
      }

      final tempDir = Directory.systemTemp;
      tempFile = File('${tempDir.path}/ocr_input_${DateTime.now().microsecondsSinceEpoch}.png');
      await tempFile.writeAsBytes(bytesToProcess);

      final inputImage = InputImage.fromFile(tempFile);
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

      return recognizedText.text;
    } catch (e) {
      if (e is UnsupportedImageFormatException) {
        rethrow;
      }
      if (e.toString().contains('OutOfMemory') || e.toString().contains('OOM')) {
        throw OcrOomException("Native OCR Out of Memory: $e");
      }
      if (e.toString().contains('not ready') || e.toString().contains('downloading')) {
        throw ModelNotReadyException("MLKit model downloading/not ready: $e");
      }
      throw Exception("MLKit native failure: $e");
    } finally {
      if (tempFile != null) {
        try {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } catch (_) {}
      }
    }
  }

  void dispose() {
    _textRecognizer.close();
  }
}

class MockOcrService implements OcrService {
  String stubbedOutput = "";
  bool shouldThrowOom = false;
  bool shouldThrowModelNotReady = false;
  bool shouldThrowUnsupportedFormat = false;
  bool shouldThrowGeneric = false;

  @override
  Future<String> recognizeText(Uint8List imageBytes, {Rect? roi}) async {
    if (shouldThrowOom) {
      throw OcrOomException("Native OCR Out of Memory");
    }
    if (shouldThrowModelNotReady) {
      throw ModelNotReadyException("MLKit model downloading");
    }
    if (shouldThrowUnsupportedFormat) {
      throw UnsupportedImageFormatException("Unsupported image format");
    }
    if (shouldThrowGeneric) {
      throw Exception("MLKit native failure");
    }

    if (imageBytes.length == 2 && imageBytes[0] == 0x99 && imageBytes[1] == 0x99) {
      throw UnsupportedImageFormatException("Format invalid (RGB565 simulated)");
    }

    if (roi != null) {
      return "[ROI Cropped] $stubbedOutput";
    }

    if (imageBytes.isNotEmpty && imageBytes.length <= 10) {
      return "";
    }

    if (stubbedOutput.length > 5000) {
      return stubbedOutput.substring(0, 5000);
    }

    final filtered = stubbedOutput.replaceAll(RegExp(r'[☀☠★]'), '');
    return filtered;
  }
}
