# Handoff Report — Explorer 1 (Milestone 3)

## 1. Observation

### Finding 5: Race Condition and Crash on `ScreenCaptureService.dispose()`
* In `lib/services/screen_capture_service.dart` lines 115-118:
  ```dart
  void dispose() {
    _stopFrameSubscription();
    _frameController.close();
  }
  ```
* In `lib/services/screen_capture_service.dart` lines 99-102:
  ```dart
  Future<void> _stopFrameSubscription() async {
    await _streamSubscription?.cancel();
    _streamSubscription = null;
  }
  ```
* In `lib/services/screen_capture_service.dart` lines 82-97:
  ```dart
  void _startFrameSubscription() {
    _streamSubscription?.cancel();
    _streamSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is Uint8List) {
          _frameController.add(event);
        }
      },
      onError: (dynamic error) {
        _handleCrash(error);
      },
      onDone: () {
        _handleDone();
      },
    );
  }
  ```
* In `lib/services/screen_capture_service.dart` lines 104-108:
  ```dart
  void _handleCrash(dynamic error) {
    _isCapturing = false;
    _stopFrameSubscription();
    _frameController.addError(error);
  }
  ```

### Finding 6: Concurrent Start/Stop Capture Race Condition
* In `lib/services/screen_capture_service.dart` lines 25-45 (start capture logic):
  ```dart
  Future<bool> startCapture({int width = 1920, int height = 1080, int x = 0, int y = 0}) async {
    validateConfig(width, height, x, y);

    if (_isCapturing) {
      return false;
    }

    try {
      final bool? result = await _methodChannel.invokeMethod<bool>('startCapture', {
        'width': width,
        'height': height,
        'x': x,
        'y': y,
      });

      if (result == true) {
        _isCapturing = true;
        _startFrameSubscription();
        return true;
      }
      return false;
  ```
* In `lib/services/screen_capture_service.dart` lines 52-64 (stop capture logic):
  ```dart
  Future<bool> stopCapture() async {
    if (!_isCapturing) {
      return true;
    }

    try {
      final bool? result = await _methodChannel.invokeMethod<bool>('stopCapture');
      if (result == true) {
        _isCapturing = false;
        await _stopFrameSubscription();
        return true;
      }
  ```

### Finding 7: `checkIsCapturing()` Out-of-Sync with Stream Subscription
* In `lib/services/screen_capture_service.dart` lines 72-80:
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

### Logic Chain for Finding 5 (Race Condition and Crash on `ScreenCaptureService.dispose()`)
1. **Fact**: `_stopFrameSubscription()` executes `await _streamSubscription?.cancel()`, which is an asynchronous operation.
2. **Fact**: `dispose()` calls `_stopFrameSubscription()` but does not (and cannot easily, due to synchronous `dispose` signature) await it, immediately proceeding to call `_frameController.close()`.
3. **Fact**: The underlying `_eventChannel` may still push a message (a new frame or an error) during the time-gap between calling `cancel()` and the cancel actually completing natively.
4. **Fact**: When a message arrives, the Dart listener triggers `_frameController.add(event)` or `_handleCrash` -> `_frameController.addError(error)`.
5. **Conclusion**: Since the broadcast stream controller `_frameController` was closed in step 2, adding any event/error throws a `StateError` ("Cannot add event after close" or "Cannot add error after close"), crashing the application.
6. **Solution**: Add guard checks `if (!_frameController.isClosed)` before invoking `.add()` and `.addError()`. Also introduce an `_isDisposed` flag to block any method execution on a disposed service instance.

### Logic Chain for Finding 6 (Concurrent Start/Stop Capture Race Condition)
1. **Fact**: `startCapture()` and `stopCapture()` are asynchronous methods that modify the shared `_isCapturing` flag based on the result of asynchronous platform method channel invocations (`invokeMethod`).
2. **Fact**: There is no serialization or locking mechanism around these calls.
3. **Fact**: If a caller calls `startCapture()`, it checks `_isCapturing` (which is `false`), and yields control to wait for the platform channel `startCapture` call to return.
4. **Fact**: If a caller invokes `stopCapture()` before that call returns, `stopCapture()` sees `_isCapturing` is still `false` (since `startCapture` hasn't updated it yet), and immediately returns `true` without executing the platform call or cancelling subscriptions.
5. **Fact**: When the native `startCapture` returns `true`, Dart sets `_isCapturing = true` and starts streaming frames, despite the user's intent to stop capture.
6. **Conclusion**: Concurrent or back-to-back calls leave the service in an inconsistent, leaking state.
7. **Solution**: Use an asynchronous lock (Mutex) based on Dart `Future` chaining to serialize calls to `startCapture()`, `stopCapture()`, and `checkIsCapturing()`. Chaining operations ensures they execute strictly in order of invocation.

### Logic Chain for Finding 7 (`checkIsCapturing()` Out-of-Sync with Stream Subscription)
1. **Fact**: `checkIsCapturing()` queries the platform channel's active capture status and updates `_isCapturing`.
2. **Fact**: `checkIsCapturing()` does not manage the frame stream subscription `_streamSubscription`.
3. **Fact**: If the platform capture is active (e.g. started externally or survived app lifecycle suspension) but `_streamSubscription` is `null`, the stream will never receive frames, despite `isCapturing` returning `true`.
4. **Conclusion**: `checkIsCapturing()` can get out-of-sync with the stream subscription, resulting in a silent failure where the UI shows active capture but no images arrive.
5. **Solution**: Update `checkIsCapturing()` to start the stream subscription (`_startFrameSubscription()`) if the native channel returns `true` and the subscription is `null`. If the native channel returns `false`, cancel any active subscription (`_stopFrameSubscription()`).

---

## 3. Caveats
* **Platform Resumption State**: While checking native state upon app lifecycle resumption is recommended, this depends on the hosting widget or app-state coordinator properly calling `checkIsCapturing()` when transitioning from background to foreground.
* **Synchronous Disposal**: Dart `dispose()` functions are synchronous. Thus, the actual native channel stream cancellation will always complete asynchronously after the service object is destroyed. Relying on `_frameController.isClosed` guards is the correct and standard solution here.

---

## 4. Conclusion
We recommend implementing a complete, non-breaking fix for Findings 5, 6, and 7 inside `lib/services/screen_capture_service.dart`, and writing accompanying unit tests in `test/services/screen_capture_test.dart`.

The fix strategy is structured as follows:
1. **Mutex Lock Serialization**: Implement a simple async task queue (`_runWithLock`) in the service to serialize state changes and platform calls.
2. **Guard Stream Controller Close**: Check `!_frameController.isClosed` before every call to `_frameController.add` and `_frameController.addError` in stream listeners.
3. **Life-Cycle & State Synchronization**: Update `checkIsCapturing` to synchronize stream subscriptions based on native capture status.
4. **Test Suite Expansion**: Add tests `TC-T2-F1-06`, `TC-T2-F1-07`, and `TC-T2-F1-08` verifying these three respective fix mechanisms.

Proposed patch files have been created in the agent workspace:
- `screen_capture_service.patch`
- `screen_capture_test.patch`

---

## 5. Verification Method

To verify these changes:
1. Apply the patches in the workspace:
   ```powershell
   git apply .agents/explorer_m3_1/screen_capture_service.patch
   git apply .agents/explorer_m3_1/screen_capture_test.patch
   ```
2. Run the test suite:
   ```powershell
   flutter test test/services/screen_capture_test.dart
   ```
3. Verify that all 8 test cases pass successfully.
