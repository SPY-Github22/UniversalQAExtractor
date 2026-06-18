# Handoff Report: Screen Capture Scaffolding Fix Strategy (Explorer 2)

## 1. Observation

During our investigation of the `UniversalQAExtractor` codebase, we analyzed three specific findings from the reviewer's report:
- **Finding 5**: Race Condition and Crash on `ScreenCaptureService.dispose()`
- **Finding 6**: Concurrent Start/Stop Capture Race Condition
- **Finding 7**: `checkIsCapturing()` Out-of-Sync with Stream Subscription

The relevant source files and code fragments are:

### A. `lib/services/screen_capture_service.dart`

- **Lines 115-118 (`dispose`)**:
```dart
  void dispose() {
    _stopFrameSubscription();
    _frameController.close();
  }
```

- **Lines 82-97 (`_startFrameSubscription`)**:
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

- **Lines 104-108 (`_handleCrash`)**:
```dart
  void _handleCrash(dynamic error) {
    _isCapturing = false;
    _stopFrameSubscription();
    _frameController.addError(error);
  }
```

- **Lines 25-50 (`startCapture`)**:
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
    } on PlatformException {
      _isCapturing = false;
      rethrow;
    }
  }
```

- **Lines 52-70 (`stopCapture`)**:
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
      return false;
    } on PlatformException {
      _isCapturing = false;
      await _stopFrameSubscription();
      rethrow;
    }
  }
```

- **Lines 72-80 (`checkIsCapturing`)**:
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

### B. `test/services/screen_capture_test.dart`
- Currently tests the happy path and basic error modes (e.g. invalid inputs, double starts, permissions) but lacks concurrent execution checks, checkIsCapturing auto-subscription checks, or dispose race-condition testing.

---

## 2. Logic Chain

### Finding 5: Race Condition and Crash on `dispose()`
1. `dispose()` initiates an asynchronous cancellation of the native event stream subscription (`_stopFrameSubscription()`) but synchronously and immediately closes the broadcast `_frameController` (Observation A, `dispose`).
2. There is a small window of time before the platform subscription is fully cancelled. If the native event channel emits an event, error, or done signal during this window, the Dart listener callbacks in `_startFrameSubscription` will be executed.
3. These callbacks call `_frameController.add(event)` or `_frameController.addError(error)` (Observation A, `_startFrameSubscription` & `_handleCrash`).
4. Since `_frameController` is already closed, calling `add()` or `addError()` throws a `StateError` ("Cannot add event after close"), crashing the application.
5. **Conclusion**: Guarding all stream emissions with `!_frameController.isClosed` checks and cleanly canceling the subscription synchronously during `dispose()` will prevent this crash.

### Finding 6: Concurrent Start/Stop Capture Race Condition
1. Both `startCapture()` and `stopCapture()` read and write the `_isCapturing` field only after invoking their respective asynchronous method channel calls (Observation A, `startCapture` & `stopCapture`).
2. If `startCapture()` is called, it verifies `_isCapturing` is `false` and awaits `invokeMethod<bool>('startCapture')`.
3. If `stopCapture()` is called immediately after while `startCapture()` is still awaiting, it sees `_isCapturing` is still `false` (since start has not completed) and exits early, returning `true` without calling the native channel (Observation A, `stopCapture` lines 53-55).
4. Once `startCapture()` completes, it sets `_isCapturing = true` and starts the frame stream subscription. The application remains in a capturing state, violating the user's intent to stop it.
5. **Conclusion**: To prevent interleaved executions, all async operations (`startCapture`, `stopCapture`, `checkIsCapturing`) must be serialized. Implementing a lightweight synchronized transaction queue (via a completer chain) ensures that each request waits for previous requests to complete before reading or writing states.

### Finding 7: `checkIsCapturing()` Out-of-Sync with Stream Subscription
1. `checkIsCapturing()` queries the native side for capture status and updates the local field `_isCapturing` (Observation A, `checkIsCapturing`).
2. If the native side was started externally (or on application recovery from a suspended state) and is capturing, `checkIsCapturing()` sets `_isCapturing = true`. However, it does not check or start the local stream subscription `_startFrameSubscription()`.
3. As a result, the application indicates it is capturing (`_isCapturing == true`), but the `frameStream` remains inactive because the native event channel is not being listened to.
4. Conversely, if native capturing is stopped externally, the subscription continues running locally, leaking resources.
5. **Conclusion**: `checkIsCapturing()` must reconcile the stream subscription state: starting the subscription if capturing is active and no subscription exists, and cancelling the subscription if capturing is inactive.

---

## 3. Caveats

- We assumed that all platform channel calls (`startCapture`, `stopCapture`, `isCapturing`) return timely and do not hang indefinitely. If a native call hangs, subsequent operations in the serialized queue will also wait. However, this is expected behavior for hardware-bound APIs, and platform timeouts are handled on the native side.
- This investigation was read-only and did not modify the files. Command execution (`flutter test`) timed out on permissions, which is consistent with the initial review report, so we validated the behavior via strict static code tracing and logical validation.

---

## 4. Conclusion & Concrete Fix Strategy

To resolve the findings comprehensively, we recommend the following changes to `lib/services/screen_capture_service.dart` and `test/services/screen_capture_test.dart`.

### A. Proposed Code Change for `lib/services/screen_capture_service.dart`

```dart
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';

class ScreenCaptureService {
  static const MethodChannel _methodChannel =
      MethodChannel('com.universalqaextractor.mobile/screen_capture');
  static const EventChannel _eventChannel =
      EventChannel('com.universalqaextractor.mobile/frame_stream');

  bool _isCapturing = false;
  bool get isCapturing => _isCapturing;

  StreamSubscription<dynamic>? _streamSubscription;
  final _frameController = StreamController<Uint8List>.broadcast();

  Stream<Uint8List> get frameStream => _frameController.stream;

  // Transaction queue to serialize start, stop, and status check operations
  Future<void>? _pendingOperation;

  Future<T> _synchronized<T>(Future<T> Function() action) async {
    final previous = _pendingOperation;
    final completer = Completer<void>();
    _pendingOperation = completer.future;

    try {
      if (previous != null) {
        await previous;
      }
      return await action();
    } finally {
      completer.complete();
      if (_pendingOperation == completer.future) {
        _pendingOperation = null;
      }
    }
  }

  void validateConfig(int width, int height, int x, int y) {
    if (width <= 0 || height <= 0 || x < 0 || y < 0) {
      throw ArgumentError('Invalid configuration parameters: resolution $width x $height, offset ($x, $y)');
    }
  }

  Future<bool> startCapture({int width = 1920, int height = 1080, int x = 0, int y = 0}) {
    return _synchronized(() async {
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
      } on PlatformException {
        _isCapturing = false;
        rethrow;
      }
    });
  }

  Future<bool> stopCapture() {
    return _synchronized(() async {
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
        return false;
      } on PlatformException {
        _isCapturing = false;
        await _stopFrameSubscription();
        rethrow;
      }
    });
  }

  Future<bool> checkIsCapturing() {
    return _synchronized(() async {
      try {
        final bool? result = await _methodChannel.invokeMethod<bool>('isCapturing');
        final isCapturingNow = result ?? false;
        _isCapturing = isCapturingNow;

        if (isCapturingNow) {
          if (_streamSubscription == null) {
            _startFrameSubscription();
          }
        } else {
          await _stopFrameSubscription();
        }
        return _isCapturing;
      } on PlatformException {
        return _isCapturing;
      }
    });
  }

  void _startFrameSubscription() {
    if (_frameController.isClosed) return;
    _streamSubscription?.cancel();
    _streamSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (!_frameController.isClosed && event is Uint8List) {
          _frameController.add(event);
        }
      },
      onError: (dynamic error) {
        if (!_frameController.isClosed) {
          _handleCrash(error);
        }
      },
      onDone: () {
        if (!_frameController.isClosed) {
          _handleDone();
        }
      },
    );
  }

  Future<void> _stopFrameSubscription() async {
    await _streamSubscription?.cancel();
    _streamSubscription = null;
  }

  void _handleCrash(dynamic error) {
    _isCapturing = false;
    _stopFrameSubscription();
    if (!_frameController.isClosed) {
      _frameController.addError(error);
    }
  }

  void _handleDone() {
    _isCapturing = false;
    _stopFrameSubscription();
  }

  void dispose() {
    _streamSubscription?.cancel();
    _streamSubscription = null;
    _frameController.close();
  }
}
```

### B. Proposed Test Cases to Add to `test/services/screen_capture_test.dart`

To verify these changes, add the following test cases in `test/services/screen_capture_test.dart`:

```dart
  test('TC-T2-F1-06: Dispose during active streaming does not crash', () async {
    await service.startCapture();
    service.dispose();
    
    // Simulate native frame delivery after dispose - should not crash
    final testFrame = Uint8List.fromList([0x00, 0x01]);
    expect(() => simulateNativeFrame(testFrame), returnsNormally);
  });

  test('TC-T2-F1-07: Concurrent start and stop are serialized', () async {
    // Trigger start and immediately trigger stop without awaiting start first
    final startFuture = service.startCapture();
    final stopFuture = service.stopCapture();
    
    final results = await Future.wait([startFuture, stopFuture]);
    
    // First (start) should return true, second (stop) should return true
    expect(results[0], isTrue);
    expect(results[1], isTrue);
    expect(service.isCapturing, isFalse);
    
    // Method call log should show startCapture then stopCapture in order
    expect(methodCallLog.length, 2);
    expect(methodCallLog[0].method, 'startCapture');
    expect(methodCallLog[1].method, 'stopCapture');
  });

  test('TC-T2-F1-08: checkIsCapturing reconciles stream subscription', () async {
    // Simulate native side capturing externally
    isCapturingMock = true;
    
    // Query status
    final isCapturing = await service.checkIsCapturing();
    expect(isCapturing, isTrue);
    expect(service.isCapturing, isTrue);
    
    // The stream subscription should have been started. Let's verify by simulating a frame
    final List<Uint8List> receivedFrames = [];
    final subscription = service.frameStream.listen((frame) {
      receivedFrames.add(frame);
    });
    
    final testFrame = Uint8List.fromList([0x99]);
    simulateNativeFrame(testFrame);
    await Future<void>.delayed(Duration.zero);
    
    expect(receivedFrames.length, 1);
    expect(receivedFrames[0], equals(testFrame));
    
    await subscription.cancel();
  });
```

---

## 5. Verification Method

Once the changes are implemented, run the following test commands to verify the fix:

### Commands:
```powershell
flutter test test/services/screen_capture_test.dart
```

### Invalidation Conditions:
- If a `StateError` ("Cannot add event after close") occurs during the tests (especially `TC-T2-F1-06`), the `isClosed` guards are improperly configured.
- If `TC-T2-F1-07` fails (e.g. `service.isCapturing` remains `true` or method logs are out of order), the serialization/locking logic is broken or bypassed.
- If `TC-T2-F1-08` fails (e.g. frame is not received after `checkIsCapturing`), the subscription reconciliation logic is not properly starting the subscription.
