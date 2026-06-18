## 2026-06-17T21:13:32Z
You are the Worker for Milestone 1 (Iteration 3).
Your working directory is d:\Projects\UniversalQAExtractor\mobile\.agents\worker_m1_3.
Your task is to fix the critical bugs and compliance issues identified by the reviewers and challengers:

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A Forensic Auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Follow these step-by-step instructions:

1. Update `pubspec.yaml`:
   - Add the `image: ^4.2.0` package under `dependencies`.

2. Refactor `lib/services/ocr_service.dart`:
   - Remove the hardcoded `[0x99, 0x99]` check in `MlKitOcrService`.
   - Implement a genuine `_isValidImageHeader(Uint8List bytes)` method checks for PNG, JPEG, GIF, and BMP magic bytes. Throw `UnsupportedImageFormatException("Format invalid")` if the bytes are empty or do not match a valid header.
   - Implement cropping for ROI in `MlKitOcrService.recognizeText`:
     If `roi != null`, decode the image using `package:image/image.dart` (`img.decodeImage`), crop it using `img.copyCrop` to the specified rectangle, and encode it back (`img.encodePng`) to get the cropped `Uint8List` before writing to the temp file.
   - Fix the disk resource leak by writing a `try-catch-finally` block. In the `finally` block, verify if the temporary file exists and delete it.

3. Refactor `lib/services/pipeline_coordinator.dart`:
   - Introduce a `bool _isProcessingFrame = false;` flag.
   - In `start()`, check if `_isProcessingFrame` is true. If it is, log that the frame is dropped due to concurrent processing and return.
   - Otherwise, set `_isProcessingFrame = true` before processing the frame, and wrap the frame processing in a `try-finally` block, resetting `_isProcessingFrame = false` in the `finally` block.

4. Update unit tests in `test/services/ocr_service_test.dart` to make sure they match these changes and that all tests pass.

Please write these changes directly using file-writing tools. Document the files changed/created in `handoff.md` in your working directory. Please report back when done.
