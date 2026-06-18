# Handoff Report - Milestone 3 & 4 Adversarial Review

## 1. Observation
- In `d:\Projects\UniversalQAExtractor\mobile\lib\services\ocr_service.dart`:
  - **Line 97-99**: The service writes a file on every frame to temporary storage:
    ```dart
    final tempDir = Directory.systemTemp;
    tempFile = File('${tempDir.path}/ocr_input_${DateTime.now().microsecondsSinceEpoch}.png');
    await tempFile.writeAsBytes(bytesToProcess);
    ```
  - **Line 83-95**: The service skips cropping if `decoded` is null, despite `roi` being specified:
    ```dart
    if (roi != null) {
      final decoded = img.decodeImage(imageBytes);
      if (decoded != null) {
        final cropped = img.copyCrop(
          decoded,
          x: roi.left.round(),
          y: roi.top.round(),
          ...
        );
        bytesToProcess = Uint8List.fromList(img.encodePng(cropped));
      }
    }
    ```
  - **Line 86-91**: Bounding box coordinates passed as ROI are passed directly into `img.copyCrop` without clamping to the decoded image width/height.
- In `d:\Projects\UniversalQAExtractor\mobile\lib\services\screen_capture_service.dart`:
  - **Line 19-23**: Configuration validation only checks for negative or <=0 values:
    ```dart
    void validateConfig(int width, int height, int x, int y) {
      if (width <= 0 || height <= 0 || x < 0 || y < 0) {
        throw ArgumentError('Invalid configuration parameters: resolution $width x $height, offset ($x, $y)');
      }
    }
    ```
  - **Line 82-97**: Stream subscription to native events is cancelled on stop or crash, but `_frameController` (the broadcast stream controller) is never closed:
    ```dart
    void _startFrameSubscription() {
      _streamSubscription?.cancel();
      _streamSubscription = _eventChannel.receiveBroadcastStream().listen( ... )
    }
    ```
  - **Line 58-64**: If the platform channel `stopCapture` returns `false`, `_isCapturing` remains `true` and the event channel is not cancelled:
    ```dart
    final bool? result = await _methodChannel.invokeMethod<bool>('stopCapture');
    if (result == true) {
      _isCapturing = false;
      await _stopFrameSubscription();
      return true;
    }
    return false;
    ```

## 2. Logic Chain
1. By writing a new temporary file on every frame processing request (Observation 1), the service introduces heavy disk IO. In continuous streaming at typical video framerates (e.g. 10+ FPS), this causes flash wear and CPU throttling.
2. If a malformed frame is received and `img.decodeImage` returns `null`, the cropping condition is bypassed but execution continues (Observation 2). Thus, the entire uncropped screen is processed. If the user defined a Region of Interest to keep personal screen details private, this acts as a privacy bypass.
3. Passing coordinate values larger than 32-bit maximums (Observation 4) propagates them directly to the native host channel. Since native hosts parse standard dimensions as 32-bit signed integers, this can trigger native runtime exceptions or memory allocation overflows.
4. Calling `stopCapture` or encountering native stream errors cancels the platform stream subscription but keeps the broadcast `_frameController` open (Observation 5). Any Dart listener utilizing `await for` on `frameStream` will hang indefinitely waiting for stream completion.

## 3. Caveats
- Hardware-specific native engine performance (Android MediaProjection / iOS ReplayKit memory bounds) and MLKit C++ binary limitations could not be physically measured because the environment does not provide physical emulator/device runtime targets.

## 4. Conclusion
The implementation works under normal happy-path mock scenarios but possesses significant edge-case risks under sustained workloads (IO degradation), boundary conditions (coordinate overflows, out-of-bounds crops), and unexpected input failures (silent privacy bypass on decoding errors). The newly written `adversarial_stress_test.dart` file successfully targets these areas.

## 5. Verification Method
- Run the Flutter test suite on a developer machine:
  ```powershell
  cd d:\Projects\UniversalQAExtractor\mobile
  flutter test test/services/adversarial_stress_test.dart
  ```
- Inspect findings detail:
  `d:\Projects\UniversalQAExtractor\mobile\.agents\challenger_m3_m4_1\challenge.md`
