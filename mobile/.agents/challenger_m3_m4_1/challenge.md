# Adversarial Review Challenge Report — Screen Capture & OCR Services

## Challenge Summary

**Overall risk assessment**: HIGH

This adversarial review identified critical architectural and boundary vulnerabilities across the Screen Capture Service (Milestone 3) and the OCR Service (Milestone 4). The most severe concerns involve silent failures in privacy boundaries (ROI cropping bypass on corrupted decodes), potential device-wear / IO-exhaustion under sustained capture stream workloads, and native integer overflow vulnerability on coordinate boundaries.

---

## Challenges

### [High] Challenge 1: Flash Storage Degradation under Continuous Workload
- **Assumption challenged**: Writing per-frame temporary PNG files to disk is acceptable for continuous streaming pipelines.
- **Attack scenario**: A user activates sustained capture mode (Tier 4 workload) at 1 FPS or higher. For each frame, the app writes a temporary PNG file to disk and subsequently deletes it. Over a 1-hour session at 1 FPS, this performs 3,600 file creation, write, and deletion operations. At standard video rates (e.g., 10-30 FPS), it translates to 36,000–108,000 disk writes per hour.
- **Blast radius**: High disk IO bottlenecks, increased power consumption (battery drain), thermal throttling, and hardware wear on the mobile device's flash memory (eMMC/UFS).
- **Mitigation**: Redesign `MlKitOcrService` to avoid disk writes entirely. Convert the frame's `Uint8List` bytes into a raw pixel buffer (YUV/RGBA) in memory and utilize `InputImage.fromBytes` with format metadata.

### [High] Challenge 2: Silent Privacy Breach on Image Decoding Failure
- **Assumption challenged**: Bounding-box coordinates (Region of Interest - ROI) are always correctly cropped prior to OCR analysis.
- **Attack scenario**: A corrupted frame (e.g., only magic bytes present or data corrupted during streaming) is received, causing `img.decodeImage(imageBytes)` to return `null`. The code silently ignores the null result, skips cropping, and writes the entire uncropped image bytes to disk to be processed by MLKit.
- **Blast radius**: Privacy violation. If the user configured an ROI to capture only a private chat window, a temporary decoding failure will cause the entire screen (including status bar, notifications, and background apps) to be sent to the OCR analyzer, bypassing the ROI privacy boundary.
- **Mitigation**: If `roi != null` and `img.decodeImage` returns `null`, the service must throw an `UnsupportedImageFormatException` or `DecodingException` instead of falling back to processing the full image.

### [Medium] Challenge 3: Stream Listener Hanging on Capture Termination
- **Assumption challenged**: Subscribers to `ScreenCaptureService.frameStream` will receive a termination or close event when capture stops.
- **Attack scenario**: When the user calls `stopCapture` or the native side crashes (triggering `_handleCrash` / `_handleDone`), the subscription to the native `EventChannel` is cancelled. However, the internal broadcast `_frameController` is never completed or closed.
- **Blast radius**: If a consumer consumes the stream asynchronously using `await for (final frame in captureService.frameStream)`, the consumer's loop will hang indefinitely when the capture stops, causing memory leaks or frozen UI components waiting for the stream to close.
- **Mitigation**: Emit a close event or complete the stream controller when capturing status transitions to `false` or during the disposal of `ScreenCaptureService`.

### [Medium] Challenge 4: Out-of-Bounds ROI Coordinates Crash
- **Assumption challenged**: Bounding box coordinates passed as ROI are always valid and fit inside the frame boundaries.
- **Attack scenario**: A user selects an ROI that falls outside the frame boundaries (e.g., image is 100x100, but ROI is defined as `Rect.fromLTWH(80, 80, 50, 50)`).
- **Blast radius**: `img.copyCrop` is called with invalid parameters, which causes an unhandled boundary/range exception (`RangeError`) in the Dart image library, crashing the OCR processing pipeline.
- **Mitigation**: Implement coordinate clamping to guarantee that the cropping rectangle is restricted to the bounds of the decoded image:
  ```dart
  final cropX = roi.left.clamp(0, decoded.width).round();
  final cropY = roi.top.clamp(0, decoded.height).round();
  final cropW = roi.width.clamp(0, decoded.width - cropX).round();
  final cropH = roi.height.clamp(0, decoded.height - cropY).round();
  ```

### [Medium] Challenge 5: Native Integer Overflow on Large Configuration Parameters
- **Assumption challenged**: Input parameters to `startCapture` (width, height, x, y) are validated only to be positive.
- **Attack scenario**: Extremely large integers (e.g., `999999999999` exceeding signed 32-bit integer limits) are passed. They bypass the `validateConfig` checks (since they are > 0) and are sent directly to the native `MethodChannel`.
- **Blast radius**: The native platform side attempts to parse these as 32-bit values, causing an integer overflow, crash, or memory allocation error (e.g., attempting to allocate a frame buffer of negative/overflowed size).
- **Mitigation**: Enforce maximum limits in `validateConfig` matching maximum realistic screen resolutions (e.g., 8K width/height limits) and coordinates.

---

## Stress Test Results

| Scenario / Test ID | Expected Behavior | Actual/Predicted Behavior | Pass/Fail |
|--------------------|-------------------|---------------------------|-----------|
| **SC-ADV-01**: Max 32-bit Integer Overflow | Validate parameters on Dart side or handle gracefully. | Propagates huge integers directly to MethodChannel. Native crash risk. | **FAIL** |
| **SC-ADV-02**: Platform channel returning mismatch type | Throw `TypeError` or handle gracefully. | Throws `TypeError` in invokeMethod, state remains consistent. | **PASS** |
| **SC-ADV-03**: Platform channel returning null | Handles null return gracefully and returns false. | Returns false, does not crash. | **PASS** |
| **SC-ADV-04**: Rapid Start-Stop cycle stress | No resource leak, state machine remains consistent. | State machine cleans up resources and resets state to idle. | **PASS** |
| **SC-ADV-05**: Native `stopCapture` returns false | Invalidate capture state or roll back. | `_isCapturing` remains `true` and the subscription is active. | **FAIL** |
| **SC-ADV-06**: Malformed frame stream event | Ignores non-Uint8List objects or throws error. | Ignores malformed types silently. | **PASS** |
| **OCR-ADV-01**: ROI Coordinates out of bounds | Handle gracefully or crop within limits. | Throws unhandled RangeError from `img.copyCrop` library. | **FAIL** |
| **OCR-ADV-02**: Negative ROI Coordinates | Handle gracefully or clamp to 0. | Throws unhandled RangeError or empty crop exception. | **FAIL** |
| **OCR-ADV-03**: Truncated Image Bytes (Valid Magic Headers) | Throw format validation failure or decoding exception. | Bypasses header check, `img.decodeImage` returns null, skips cropping, writes corrupt file to disk. | **FAIL** |
| **OCR-ADV-07**: High concurrency OCR requests | Safe file naming, queueing, and resource cleaning. | Writes temporary files with microsecond timestamps. Under extreme concurrency, files can conflict. | **FAIL** |

---

## Unchallenged Areas

- **Native MLKit Engine internals**: The actual neural network execution and character segmentation of MLKit are handled inside Google's C++ library binaries, which cannot be stress-tested in local Dart unit-test environments.
- **Physical Device Frame Buffer Allocation (Android MediaProjection / iOS ReplayKit)**: The hardware video pipeline constraints (OOMs due to device-specific VRAM constraints) cannot be tested in host-side unit tests.
