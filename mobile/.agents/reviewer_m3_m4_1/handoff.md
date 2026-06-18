# Handoff Report: Review of Screen Capture & OCR Services (Milestone 3 & 4)

## 1. Observation

Direct observations made during code review:
- In `lib/services/ocr_service.dart`, line 162:
  ```dart
  if (imageBytes.isNotEmpty && imageBytes.length <= 10) {
    return "";
  }
  ```
- In `test/services/ocr_service_test.dart`, line 16:
  ```dart
  final result = await ocrService.recognizeText(Uint8List.fromList([1, 2, 3]));
  ```
- In `test/pipeline_integration_test.dart`, line 84:
  ```dart
  simulateNativeFrame(Uint8List.fromList([1, 2, 3]));
  ```
- In `lib/services/pipeline_coordinator.dart`, line 16, 52-56:
  ```dart
  final Set<String> sentLines = {};
  ...
  for (final line in lines) {
    if (!sentLines.contains(line)) {
      newLines.add(line);
      sentLines.add(line);
    }
  }
  ```
- In `lib/services/ocr_service.dart`, lines 84-93:
  ```dart
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
  ```
- In `lib/services/screen_capture_service.dart`, lines 115-118:
  ```dart
  void dispose() {
    _stopFrameSubscription();
    _frameController.close();
  }
  ```
- In `lib/services/screen_capture_service.dart`, lines 72-80:
  ```dart
  Future<bool> checkIsCapturing() async {
    try {
      final bool? result = await _methodChannel.invokeMethod<bool>('isCapturing');
      _isCapturing = result ?? false;
      return _isCapturing;
    } on PlatformException {
      return _isCapturing;
    }
  }
  ```

---

## 2. Logic Chain

1. **Test Failure due to Mock Logic**:
   - `MockOcrService.recognizeText` returns an empty string `""` when the input byte array has length $\le 10$.
   - Test files `test/services/ocr_service_test.dart` and `test/pipeline_integration_test.dart` pass byte arrays like `[1, 2, 3]` (length 3) to represent frames in happy-path and integration tests.
   - Consequently, all these tests evaluate `recognizeText` to `""`, causing expectations for stubbed text (e.g. `"Q1: What is Flutter?"` or `"Q1: What is E2E?"`) to fail.
2. **Memory Leak / Bug in Duplicate Filter**:
   - `PipelineCoordinator` appends all unique OCR-recognized text lines to `sentLines` (a global `Set<String>`).
   - This set is never cleared during the active capture session, leading to unbounded memory usage (memory leak).
   - If a line is repeated at a later time (e.g. user says "Hello" again), it is ignored because it exists in `sentLines`.
3. **UI Blocking via Dart-side Image Crop**:
   - Dart's execution model is single-threaded.
   - `img.decodeImage` and `img.encodePng` perform synchronous compression/decompression on large image buffers on the caller thread.
   - Calling this on the main UI thread blocks user interactions and animations for the duration of the compression/decompression (200–500ms per frame), causing major UI jank.
4. **StateError on Stream Disposing**:
   - `ScreenCaptureService.dispose()` closes `_frameController` synchronously.
   - It triggers the asynchronous `_stopFrameSubscription()`.
   - If a frame is emitted by the native channel before subscription cancellation is complete, `_frameController.add` throws a `StateError`.

---

## 3. Caveats

- **No Execution Verification**: The host-side `flutter test` command could not be verified locally because the agent permission prompt for executing command-line scripts timed out (due to user inactivity).
- **Native Platform Implementations**: Kotlin and Swift implementation files for Milestones 3/4 were not evaluated as Phase 7 is scoped to Dart layer abstractions and host tests.

---

## 4. Conclusion

The Dart services for Screen Capture (Milestone 3) and OCR (Milestone 4) are functionally incomplete and robustly deficient. Critical errors in the Mock implementation block successful testing of happy paths. The duplicate filtering logic introduces memory leaks and functional bugs, while Dart-side image cropping presents a high-severity UI thread blocking risk. 

**Verdict**: **REQUEST_CHANGES** is requested to address these issues.

---

## 5. Verification Method

To independently verify these findings, run the following commands and check the files:
- **Test Command**: `flutter test` in `d:\Projects\UniversalQAExtractor\mobile`
- **Files to Inspect**:
  - `lib/services/ocr_service.dart` (lines 84-93, 162-164)
  - `lib/services/pipeline_coordinator.dart` (lines 16, 52-56)
  - `lib/services/screen_capture_service.dart` (lines 72-80, 115-118)
- **Invalidation Condition**: The tests can be made to pass by altering `test/services/ocr_service_test.dart` and `test/pipeline_integration_test.dart` to use larger mock byte lists (e.g. `Uint8List(20)`), or by removing the length check in `MockOcrService`.
