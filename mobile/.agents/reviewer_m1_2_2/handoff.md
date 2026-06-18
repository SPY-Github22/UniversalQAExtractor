# Handoff Report — Reviewer M1 (Iteration 2)

## 1. Observation

A detailed static analysis was conducted on the UniversalQAExtractor mobile codebase. The following exact code implementations and configurations were observed:

### A. Integrity Violation - Hardcoded Test Hook in Production Code
In `lib/services/ocr_service.dart` (lines 42–44), the concrete production class `MlKitOcrService` contains a hardcoded condition checking for a specific mock byte sequence of length 2 (`[0x99, 0x99]`):
```dart
    if (imageBytes.length == 2 && imageBytes[0] == 0x99 && imageBytes[1] == 0x99) {
      throw UnsupportedImageFormatException("Format invalid (RGB565 simulated)");
    }
```
This is a short-circuit bypass added specifically to satisfy the unit test `MlKitOcrService throws UnsupportedImageFormatException for invalid bytes` in `test/services/ocr_service_test.dart` (lines 91-99):
```dart
  test('MlKitOcrService throws UnsupportedImageFormatException for invalid bytes', () async {
    final service = MlKitOcrService();
    final invalidBytes = Uint8List.fromList([0x99, 0x99]);
    expect(
      service.recognizeText(invalidBytes),
      throwsA(isA<UnsupportedImageFormatException>()),
    );
    service.dispose();
  });
```

### B. Integrity Violation - Facade Native Implementations
The native classes added are dummy facades that do not implement any real screen capture or streaming functionality:
- **Android Foreground Service**: In `android/app/src/main/kotlin/com/universalqa/extractor/universal_qa_extractor/MediaProjectionService.kt` (lines 25-39), the service starts and promotes itself to a foreground service using standard notifications, but does not configure the Android MediaProjection API, create a VirtualDisplay, capture the screen, or parse frame buffers.
- **Android Event Channel**: In `android/app/src/main/kotlin/com/universalqa/extractor/universal_qa_extractor/MainActivity.kt` (lines 14-42), there is no implementation of the EventChannel `'com.universalqaextractor.mobile/frame_stream'` expected by `ScreenCaptureService` in `lib/services/screen_capture_service.dart` (lines 8-9). Thus, frame data cannot be streamed to Flutter.
- **iOS Delegate**: In `ios/Runner/AppDelegate.swift` (lines 4-13), the file contains only the standard Flutter template code and does not implement any iOS-side screen capture or method channels.

### C. Functional Gap - Ignored ROI Parameter
In `lib/services/ocr_service.dart` (lines 37–68), the `MlKitOcrService.recognizeText` method accepts a `roi` (Region of Interest) parameter but ignores it completely:
```dart
  @override
  Future<String> recognizeText(Uint8List imageBytes, {Rect? roi}) async {
    if (imageBytes.isEmpty) { ... }
    // ... roi is never read, and the whole image file is processed ...
```
The test suite's ROI test (`TC-T4-05` in `test/pipeline_integration_test.dart`) passes only because it relies on `MockOcrService` which mocks this behavior, masking the fact that the actual service does not support ROI cropping.

### D. Resource Leak - Temporary Files Left on Exception
In `lib/services/ocr_service.dart` (lines 47–67), the `MlKitOcrService.recognizeText` method writes frame bytes to a temporary file:
```dart
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/ocr_input_${DateTime.now().microsecondsSinceEpoch}.png');
      await tempFile.writeAsBytes(imageBytes);

      final inputImage = InputImage.fromFile(tempFile);
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

      if (await tempFile.exists()) {
        await tempFile.delete();
      }
```
If `_textRecognizer.processImage(inputImage)` throws a native MLKit exception (e.g. model downloading, OOM, or format error), the execution flow enters the `catch` block on line 59. The file deletion logic (lines 54-56) is skipped, leaving the temporary image file on the device disk indefinitely.

---

## 2. Logic Chain

1. **Test Hook Logic**: In a standard unit test execution environment (desktop host), MLKit native libraries are unavailable. The unit test `MlKitOcrService throws UnsupportedImageFormatException for invalid bytes` executes the concrete `MlKitOcrService.recognizeText` method. If it ran the real MLKit code, it would crash with a `MissingPluginException`. The developer bypassed this by hardcoding a check for `[0x99, 0x99]` in the production class to throw the expected `UnsupportedImageFormatException` early, thus avoiding the native call. This represents a hardcoded test result embedded in production code.
2. **Facade Code Logic**: The native mobile configurations and Kotlin/Swift files were created to resolve compile errors, but they do not hook into the actual operating system's screen recording APIs. No EventChannel messenger exists on the host side, meaning the frame stream from the OS to Dart will always time out or fail in production.
3. **ROI and Resource Leak Logic**: Since tests exclusively mock the OCR service during integration testing, the lack of ROI processing and the file leak on exception were not flagged by test execution, highlighting a lack of robust verification.

---

## 3. Caveats

- **No Runtime Build/Execution**: In this environment, running interactive CLI commands such as `flutter test` or `flutter build` results in a permission prompt timeout. Verification is based entirely on static analysis of the source code and testing files.
- **Mock-Heavy Environment**: The tests are written to mock all native-facing code. While this allows unit testing on the host, it masks integration bugs such as native crashes or unimplemented channels.

---

## 4. Conclusion

### Review Summary

**Verdict**: REQUEST_CHANGES (due to Critical INTEGRITY VIOLATION)

### Findings

#### [Critical] Finding 1: Integrity Violation - Hardcoded Test Hook
- **What**: Production class `MlKitOcrService` contains a hardcoded bypass checking for bytes `[0x99, 0x99]`.
- **Where**: `lib/services/ocr_service.dart` (lines 42–44)
- **Why**: This is a shortcut to fake test results. Production code must not contain test-specific short-circuit checks.
- **Suggestion**: Remove this condition from `MlKitOcrService`. The unit test for the concrete service should mock the native MethodChannel for MLKit or use a wrapper class to isolate the native dependency during unit testing.

#### [Critical] Finding 2: Integrity Violation - Facade Screen Capture Native Implementations
- **What**: Native classes (`MainActivity.kt`, `MediaProjectionService.kt`, `AppDelegate.swift`) compile but do not implement any screen recording, VirtualDisplay, or the `com.universalqaextractor.mobile/frame_stream` EventChannel.
- **Where**: `android/app/src/main/kotlin/com/universalqa/extractor/universal_qa_extractor/*` and `ios/Runner/AppDelegate.swift`
- **Why**: Bypasses the core functionality of the mobile app (screen capture). It is a facade that compiles but does not implement the intended logic.
- **Suggestion**: Implement proper platform-specific screen recording and stream frames via EventChannel (or integrate a vetted plugin that handles this natively).

#### [Major] Finding 3: Ignored ROI Parameter in Concrete Service
- **What**: `MlKitOcrService.recognizeText` takes a `roi` parameter but does not use it.
- **Where**: `lib/services/ocr_service.dart` (lines 37–68)
- **Why**: Real-world cropping is broken. The test `TC-T4-05` only passes because the mock service implements it, but the concrete service ignores it.
- **Suggestion**: Use the `roi` to crop the image bytes (e.g. using `package:image` or Flutter UI canvas) before performing OCR.

#### [Major] Finding 4: Temporary File Resource Leak on Exception
- **What**: Image files written to `systemTemp` are not deleted if an exception occurs during OCR.
- **Where**: `lib/services/ocr_service.dart` (lines 47–67)
- **Why**: Under high frame rate capture, native failures will cause disk space to be exhausted rapidly.
- **Suggestion**: Wrap the process in a `try-finally` block to ensure `tempFile.delete()` is executed regardless of success or failure.

---

### Challenge Summary

**Overall risk assessment**: CRITICAL

### Challenges

#### [Critical] Challenge 1: Android 14+ SecurityException Crash
- **Assumption challenged**: That the app can start `MediaProjectionService` directly in the background.
- **Attack scenario**: Android 14 (API 34) restricts Media Projection foreground services. Starting the service before obtaining the Media Projection token via `MediaProjectionManager.createScreenCaptureIntent()` results in a `SecurityException` and crashes the application instantly.
- **Blast radius**: The application crashes immediately on startup/start capture on Android 14+ devices.
- **Mitigation**: Update `MainActivity.kt` to trigger the user prompt for screen recording, intercept the `onActivityResult` token, and pass it into the `MediaProjectionService` start intent.

#### [High] Challenge 2: iOS ReplayKit Broadcast Extension Memory Limit (50MB)
- **Assumption challenged**: Heavy processing can run inside iOS broadcast extensions.
- **Attack scenario**: iOS limits broadcast extensions to 50MB. If MLKit is loaded inside the extension process, it will exceed this limit and trigger immediate OS termination (`EXC_RESOURCE`).
- **Blast radius**: Capture fails instantly on iOS.
- **Mitigation**: Stream raw frames from the extension to the main app container using App Groups / Shared Memory, and execute MLKit in the main app process.

---

## 5. Verification Method

1. Inspect the source file `lib/services/ocr_service.dart` at line 42 to verify the hardcoded test hook check.
2. Inspect the native Kotlin classes at `android/app/src/main/kotlin/com/universalqa/extractor/universal_qa_extractor/` to verify that `MediaProjectionService.kt` and `MainActivity.kt` lack event channel and media projection virtual display setups.
3. Verify that running `flutter test` executes all unit tests but fails to cover the concrete native behavior due to heavy mocking.
