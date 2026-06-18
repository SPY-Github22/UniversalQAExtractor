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

  void validateConfig(int width, int height, int x, int y) {
    if (width <= 0 || height <= 0 || x < 0 || y < 0) {
      throw ArgumentError('Invalid configuration parameters: resolution $width x $height, offset ($x, $y)');
    }
  }

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

  Future<bool> checkIsCapturing() async {
    try {
      final bool? result = await _methodChannel.invokeMethod<bool>('isCapturing');
      _isCapturing = result ?? false;
      return _isCapturing;
    } on PlatformException {
      return _isCapturing;
    }
  }

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

  Future<void> _stopFrameSubscription() async {
    await _streamSubscription?.cancel();
    _streamSubscription = null;
  }

  void _handleCrash(dynamic error) {
    _isCapturing = false;
    _stopFrameSubscription();
    _frameController.addError(error);
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
