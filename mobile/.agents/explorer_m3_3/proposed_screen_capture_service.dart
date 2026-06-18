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

  // A future that represents the currently active state transition (start/stop/check status).
  // This is used as a mutex to prevent race conditions from concurrent calls.
  Future<void>? _activeTransition;

  // Helper method to serialize operations on the capture service state.
  Future<T> _synchronized<T>(Future<T> Function() action) async {
    while (_activeTransition != null) {
      await _activeTransition;
    }
    final completer = Completer<void>();
    _activeTransition = completer.future;
    try {
      return await action();
    } finally {
      completer.complete();
      _activeTransition = null;
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
        _isCapturing = result ?? false;
        if (_isCapturing && _streamSubscription == null) {
          _startFrameSubscription();
        } else if (!_isCapturing && _streamSubscription != null) {
          await _stopFrameSubscription();
        }
        return _isCapturing;
      } on PlatformException {
        return _isCapturing;
      }
    });
  }

  void _startFrameSubscription() {
    _streamSubscription?.cancel();
    _streamSubscription = _eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (!_frameController.isClosed && event is Uint8List) {
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
    _stopFrameSubscription();
    _frameController.close();
  }
}
