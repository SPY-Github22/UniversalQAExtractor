import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_qa_extractor/services/screen_capture_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ScreenCaptureService service;
  late MethodChannel methodChannel;
  late List<MethodCall> methodCallLog;
  late bool isCapturingMock;
  late bool permissionDeniedMock;

  setUp(() {
    service = ScreenCaptureService();
    methodChannel = const MethodChannel('com.universalqaextractor.mobile/screen_capture');
    methodCallLog = <MethodCall>[];
    isCapturingMock = false;
    permissionDeniedMock = false;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (MethodCall methodCall) async {
      methodCallLog.add(methodCall);
      switch (methodCall.method) {
        case 'startCapture':
          if (permissionDeniedMock) {
            throw PlatformException(
              code: 'PERMISSION_DENIED',
              message: 'OS Permission Denied',
            );
          }
          isCapturingMock = true;
          return true;
        case 'stopCapture':
          isCapturingMock = false;
          return true;
        case 'isCapturing':
          return isCapturingMock;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
    service.dispose();
  });

  void simulateNativeFrame(Uint8List frameData) {
    const StandardMethodCodec codec = StandardMethodCodec();
    final ByteData message = codec.encodeSuccessEnvelope(frameData);
    
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      'com.universalqaextractor.mobile/frame_stream',
      message,
      (ByteData? reply) {},
    );
  }

  void simulateNativeError() {
    const StandardMethodCodec codec = StandardMethodCodec();
    final ByteData message = codec.encodeErrorEnvelope(
      code: 'DISCONNECTED',
      message: 'Platform service disconnected',
    );
    
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      'com.universalqaextractor.mobile/frame_stream',
      message,
      (ByteData? reply) {},
    );
  }

  test('TC-T1-F1-01: Start Capture Success', () async {
    expect(service.isCapturing, isFalse);
    final result = await service.startCapture();
    expect(result, isTrue);
    expect(service.isCapturing, isTrue);
    expect(methodCallLog.length, 1);
    expect(methodCallLog[0].method, 'startCapture');
  });

  test('TC-T1-F1-02: Stop Capture Success', () async {
    await service.startCapture();
    expect(service.isCapturing, isTrue);

    final result = await service.stopCapture();
    expect(result, isTrue);
    expect(service.isCapturing, isFalse);
    expect(methodCallLog.last.method, 'stopCapture');
  });

  test('TC-T1-F1-03: Query Capture Status Active', () async {
    await service.startCapture();
    final status = await service.checkIsCapturing();
    expect(status, isTrue);
    expect(methodCallLog.last.method, 'isCapturing');
  });

  test('TC-T1-F1-04: Query Capture Status Idle', () async {
    final status = await service.checkIsCapturing();
    expect(status, isFalse);
    expect(methodCallLog.last.method, 'isCapturing');
  });

  test('TC-T1-F1-05: Frame Buffer Streaming', () async {
    final List<Uint8List> receivedFrames = [];
    final subscription = service.frameStream.listen((frame) {
      receivedFrames.add(frame);
    });

    await service.startCapture();

    final testFrame = Uint8List.fromList([0x00, 0x01]);
    simulateNativeFrame(testFrame);

    await Future<void>.delayed(Duration.zero);

    expect(receivedFrames.length, 1);
    expect(receivedFrames[0], equals(testFrame));

    await subscription.cancel();
  });

  test('TC-T2-F1-01: Double Start Call Prevention', () async {
    await service.startCapture();
    expect(service.isCapturing, isTrue);
    methodCallLog.clear();

    final result = await service.startCapture();
    expect(result, isFalse);
    expect(methodCallLog, isEmpty);
  });

  test('TC-T2-F1-02: Double Stop Call Safety', () async {
    expect(service.isCapturing, isFalse);
    methodCallLog.clear();

    final result = await service.stopCapture();
    expect(result, isTrue);
    expect(methodCallLog, isEmpty);
  });

  test('TC-T2-F1-03: OS Permission Denied', () async {
    permissionDeniedMock = true;
    expect(
      service.startCapture(),
      throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'PERMISSION_DENIED')),
    );
    expect(service.isCapturing, isFalse);
  });

  test('TC-T2-F1-04: Platform Service Crash / Disconnection', () async {
    await service.startCapture();
    expect(service.isCapturing, isTrue);

    final completer = Completer<dynamic>();
    service.frameStream.listen(
      (_) {},
      onError: (err) {
        completer.complete(err);
      },
    );

    simulateNativeError();

    final error = await completer.future;
    expect(error, isA<PlatformException>());
    expect(service.isCapturing, isFalse);
  });

  test('TC-T2-F1-05: Invalid Configuration Parameters', () async {
    expect(() => service.startCapture(width: -10), throwsArgumentError);
    expect(() => service.startCapture(height: 0), throwsArgumentError);
    expect(() => service.startCapture(x: -5), throwsArgumentError);
    expect(() => service.startCapture(y: -1), throwsArgumentError);
    expect(service.isCapturing, isFalse);
  });
}
