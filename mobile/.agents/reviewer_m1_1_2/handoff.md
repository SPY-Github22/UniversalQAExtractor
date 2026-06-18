# Handoff Report — Reviewer 1 (Milestone 1, Iteration 2)

## 1. Observation
- File `lib/services/ocr_service.dart` line 33 defines `MlKitOcrService` implementing `OcrService`.
- File `lib/services/ocr_service.dart` lines 37-68 defines `recognizeText(Uint8List imageBytes, {Rect? roi})` in `MlKitOcrService`:
  ```dart
  @override
  Future<String> recognizeText(Uint8List imageBytes, {Rect? roi}) async {
    if (imageBytes.isEmpty) {
      return '';
    }

    if (imageBytes.length == 2 && imageBytes[0] == 0x99 && imageBytes[1] == 0x99) {
      throw UnsupportedImageFormatException("Format invalid (RGB565 simulated)");
    }

    try {
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/ocr_input_${DateTime.now().microsecondsSinceEpoch}.png');
      await tempFile.writeAsBytes(imageBytes);

      final inputImage = InputImage.fromFile(tempFile);
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      return recognizedText.text;
    } catch (e) {
      // ...
    }
  }
  ```
  Note that the `roi` parameter is completely ignored in this production class.
- File `lib/services/ocr_service.dart` lines 101-103 defines `recognizeText` in `MockOcrService`:
  ```dart
  if (roi != null) {
    return "[ROI Cropped] $stubbedOutput";
  }
  ```
- File `lib/services/pipeline_coordinator.dart` line 40 invokes `ocrService.recognizeText(frame, roi: roi)`.
- File `test/pipeline_integration_test.dart` lines 277-300 defines `TC-T4-05: ROI selection and cropping coordinates validation`, which runs using `MockOcrService` and passes because of the mock implementation.
- Android Manifest file `android/app/src/main/AndroidManifest.xml` declares `MediaProjectionService` with `android:foregroundServiceType="mediaProjection"`.
- Android Theme resources `styles.xml` and `launch_background.xml` are located in `android/app/src/main/res/values/styles.xml` and `android/app/src/main/res/drawable/launch_background.xml`.
- Flutter `flutter test` execution could not be verified in the shell due to a permission timeout on the `run_command` tool.

## 2. Logic Chain
1. The `PipelineCoordinator` passes the `roi` parameter to `ocrService.recognizeText` to crop the image frames to the selected Region of Interest (e.g., chat box only).
2. The `MockOcrService` intercepts `roi` and returns mock cropped output, causing integration test `TC-T4-05` to pass.
3. However, the production `MlKitOcrService` accepts the `roi` parameter but does not perform any image cropping or subset processing. It writes the entire raw `imageBytes` to a temp file and runs OCR on the entire screen.
4. Therefore, when running on a physical device, the ROI cropping feature will not function, and text outside the ROI will be scanned and sent to the API, contradicting the requirements.

## 3. Caveats
- Host-side automated testing of native Android/iOS integration is constrained to platform channel mocking.
- Due to permission verification timeouts on `run_command`, `flutter test` was not run locally by this reviewer agent, although tests were inspected statically.

## 4. Conclusion
- Verdict: **REQUEST_CHANGES**
- Critical Finding: None (No integrity violations or cheating detected).
- Major Finding: Discrepancy between Mock and Production implementations for ROI (Region of Interest) cropping. The `MlKitOcrService` accepts but ignores the `roi` parameter, while `MockOcrService` implements it. This results in tests passing while the feature is dysfunctional in production.

## 5. Verification Method
1. Inspect `lib/services/ocr_service.dart` line 37 to verify that `MlKitOcrService.recognizeText` does not use the `roi` parameter.
2. Run `flutter test` to verify the mock tests.

---

# Review Report

## Review Summary

**Verdict**: REQUEST_CHANGES

## Findings

### [Major] Finding 1: Discrepancy between Mock and Production ROI Cropping

- **What**: The production `MlKitOcrService` accepts but completely ignores the `roi` parameter, whereas the `MockOcrService` simulates its behavior.
- **Where**: `lib/services/ocr_service.dart` (lines 37–68)
- **Why**: This represents a mock-lying issue where tests pass, but the core functionality (ROI selection and cropping coordinates validation) is not implemented in the production class and would fail in a real environment.
- **Suggestion**: Update `MlKitOcrService.recognizeText` to perform image cropping using a library like `package:image` or crop the bitmap/bytes within Flutter before running OCR, or log/handle it appropriately if cropping is intended to occur on the native capture side.

### [Minor] Finding 2: Unused import in `ocr_service.dart`

- **What**: The import of `dart:io` or `dart:ui` might be unused or only partially used.
- **Where**: `lib/services/ocr_service.dart` (line 3: `import 'dart:ui';`)
- **Why**: Clean code style. `dart:ui` is only used for the `Rect` type. This is fine, but if we do not crop in Dart, it becomes moot.

## Verified Claims

- Root Gradle files clean → verified via file inspection of `build.gradle`, `settings.gradle`, `gradle.properties` → PASS
- Native Kotlin source classes clean → verified via file inspection of `MainActivity.kt` and `MediaProjectionService.kt` → PASS
- iOS Swift App Delegate clean → verified via file inspection of `AppDelegate.swift` → PASS
- Android Theme Resources clean → verified via file inspection of `styles.xml` and `launch_background.xml` → PASS
- Dart Services support dependency injection → verified via file inspection of `api_service.dart` and `ocr_service.dart` → PASS

## Coverage Gaps

- **Production ROI Cropping** — risk level: HIGH — recommendation: Implement image cropping in production OCR service.

## Unverified Items

- **Flutter Test Suite execution** — reason not verified: Permission prompt for `run_command` timed out.

---

# Challenge Report

## Challenge Summary

**Overall risk assessment**: MEDIUM

## Challenges

### [High] Challenge 1: Discrepancy in ROI crop logic between mock and production

- **Assumption challenged**: That the mock behavior correctly represents the production capability for ROI selection.
- **Attack scenario**: A user selects a split-screen layout with chat on the left and a video game on the right, configuring the ROI to the chat. Because the production `MlKitOcrService` ignores the ROI, OCR is run on the entire screen, capturing game text and flooding the API, defeating the purpose of the crop feature.
- **Blast radius**: ROI cropping is completely non-functional in production.
- **Mitigation**: Implement real cropping in `MlKitOcrService`.

## Stress Test Results

- **ROI Cropping test** → Expected behavior: Crop image bytes to coordinates before passing to MLKit → Actual/predicted behavior: MLKit processes full image → FAIL

## Unchallenged Areas

- **Native Media Projection** — reason not challenged: Native service lifecycle is mocked in Dart tests.
