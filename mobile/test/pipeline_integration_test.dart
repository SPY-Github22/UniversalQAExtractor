import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:universal_qa_extractor/services/api_service.dart';
import 'package:universal_qa_extractor/services/ocr_service.dart';
import 'package:universal_qa_extractor/services/screen_capture_service.dart';
import 'package:universal_qa_extractor/services/pipeline_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ScreenCaptureService captureService;
  late MockOcrService ocrService;
  late MethodChannel methodChannel;
  late List<MethodCall> methodCallLog;
  late bool isCapturingMock;

  setUp(() {
    captureService = ScreenCaptureService();
    ocrService = MockOcrService();
    methodChannel = const MethodChannel('com.universalqaextractor.mobile/screen_capture');
    methodCallLog = <MethodCall>[];
    isCapturingMock = false;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (MethodCall methodCall) async {
      methodCallLog.add(methodCall);
      switch (methodCall.method) {
        case 'startCapture':
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
    captureService.dispose();
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

  test('TC-T3-01: End-to-End Pipeline', () async {
    final mockHttpClient = MockClient((request) async {
      return http.Response(
        '{"status": "success", "questions": ["E2E summary"]}',
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final apiService = ApiService(httpClient: mockHttpClient, serverIp: '127.0.0.1', deviceId: 'test-device-id');
    final coordinator = PipelineCoordinator(
      captureService: captureService,
      ocrService: ocrService,
      apiService: apiService,
    );

    ocrService.stubbedOutput = "Q1: What is E2E?";
    coordinator.start();
    await captureService.startCapture();

    simulateNativeFrame(Uint8List.fromList([1, 2, 3]));
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.framesProcessed, 1);
    expect(coordinator.apiUploads.length, 1);
    expect(coordinator.apiUploads.first, "Q1: What is E2E?");
    expect(coordinator.eventLogs, contains(contains("Successfully uploaded")));

    coordinator.dispose();
  });

  test('TC-T3-02: OCR Failure blocks API request', () async {
    final mockHttpClient = MockClient((request) async {
      fail("API should not be called when OCR fails");
    });
    final apiService = ApiService(httpClient: mockHttpClient, serverIp: '127.0.0.1', deviceId: 'test-device-id');
    final coordinator = PipelineCoordinator(
      captureService: captureService,
      ocrService: ocrService,
      apiService: apiService,
    );

    ocrService.shouldThrowGeneric = true;
    coordinator.start();
    await captureService.startCapture();

    simulateNativeFrame(Uint8List.fromList([1, 2, 3]));
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.framesProcessed, 1);
    expect(coordinator.apiUploads, isEmpty);
    expect(coordinator.eventLogs, contains(contains("OCR Failure")));

    coordinator.dispose();
  });

  test('TC-T3-03: Capture stop cancels pending requests', () async {
    final mockHttpClient = MockClient((request) async {
      return http.Response('{"status": "success", "questions": ["summary"]}', 200);
    });
    final apiService = ApiService(httpClient: mockHttpClient, serverIp: '127.0.0.1', deviceId: 'test-device-id');
    final coordinator = PipelineCoordinator(
      captureService: captureService,
      ocrService: ocrService,
      apiService: apiService,
    );

    coordinator.start();
    await captureService.startCapture();
    coordinator.isOnline = false;
    ocrService.stubbedOutput = "Queued message";

    simulateNativeFrame(Uint8List.fromList([1, 2, 3]));
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.offlineQueue.length, 1);

    await coordinator.stop();
    expect(coordinator.offlineQueue, isEmpty);

    coordinator.dispose();
  });

  test('TC-T4-01: Sustained Capture Leak Test', () async {
    final mockHttpClient = MockClient((request) async {
      return http.Response('{"status": "success", "questions": ["summary"]}', 200);
    });
    final apiService = ApiService(httpClient: mockHttpClient, serverIp: '127.0.0.1', deviceId: 'test-device-id');
    final coordinator = PipelineCoordinator(
      captureService: captureService,
      ocrService: ocrService,
      apiService: apiService,
    );

    coordinator.start();
    await captureService.startCapture();

    for (int i = 0; i < 600; i++) {
      ocrService.stubbedOutput = "Frame $i text";
      simulateNativeFrame(Uint8List.fromList([i % 256]));
      await Future<void>.delayed(Duration.zero);
    }

    expect(coordinator.framesProcessed, 600);
    expect(coordinator.apiUploads.length, 600);

    coordinator.dispose();
    expect(coordinator.sentLines, isEmpty);
    expect(coordinator.offlineQueue, isEmpty);
  });

  test('TC-T4-02: Active Chat Scroll Duplicate Filter', () async {
    final mockHttpClient = MockClient((request) async {
      return http.Response('{"status": "success", "questions": ["summary"]}', 200);
    });
    final apiService = ApiService(httpClient: mockHttpClient, serverIp: '127.0.0.1', deviceId: 'test-device-id');
    final coordinator = PipelineCoordinator(
      captureService: captureService,
      ocrService: ocrService,
      apiService: apiService,
    );

    coordinator.start();
    await captureService.startCapture();

    ocrService.stubbedOutput = "Line 1\nLine 2";
    simulateNativeFrame(Uint8List.fromList([1]));
    await Future<void>.delayed(Duration.zero);

    ocrService.stubbedOutput = "Line 2\nLine 3";
    simulateNativeFrame(Uint8List.fromList([2]));
    await Future<void>.delayed(Duration.zero);

    ocrService.stubbedOutput = "Line 2\nLine 3";
    simulateNativeFrame(Uint8List.fromList([3]));
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.apiUploads.length, 2);
    expect(coordinator.apiUploads[0], "Line 1\nLine 2");
    expect(coordinator.apiUploads[1], "Line 3");

    coordinator.dispose();
  });

  test('TC-T4-03: Offline Queueing & Reconnection', () async {
    final mockHttpClient = MockClient((request) async {
      return http.Response('{"status": "success", "questions": ["summary"]}', 200);
    });
    final apiService = ApiService(httpClient: mockHttpClient, serverIp: '127.0.0.1', deviceId: 'test-device-id');
    final coordinator = PipelineCoordinator(
      captureService: captureService,
      ocrService: ocrService,
      apiService: apiService,
    );

    coordinator.start();
    await captureService.startCapture();

    coordinator.isOnline = false;

    ocrService.stubbedOutput = "Offline line 1";
    simulateNativeFrame(Uint8List.fromList([1]));
    await Future<void>.delayed(Duration.zero);

    ocrService.stubbedOutput = "Offline line 2";
    simulateNativeFrame(Uint8List.fromList([2]));
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.offlineQueue.length, 2);
    expect(coordinator.apiUploads, isEmpty);

    await coordinator.setOnline(true);

    expect(coordinator.offlineQueue, isEmpty);
    expect(coordinator.apiUploads.length, 2);
    expect(coordinator.apiUploads[0], "Offline line 1");
    expect(coordinator.apiUploads[1], "Offline line 2");

    coordinator.dispose();
  });

  test('TC-T4-04: OS Lifecycle state suspension and recovery', () async {
    final mockHttpClient = MockClient((request) async {
      return http.Response('{"status": "success", "questions": ["summary"]}', 200);
    });
    final apiService = ApiService(httpClient: mockHttpClient, serverIp: '127.0.0.1', deviceId: 'test-device-id');
    final coordinator = PipelineCoordinator(
      captureService: captureService,
      ocrService: ocrService,
      apiService: apiService,
    );

    coordinator.start();
    await captureService.startCapture();
    coordinator.isOnline = false;

    ocrService.stubbedOutput = "Background text";
    simulateNativeFrame(Uint8List.fromList([1]));
    await Future<void>.delayed(Duration.zero);

    coordinator.suspend();
    expect(coordinator.isSuspended, isTrue);
    expect(coordinator.serializedQueueState, "Background text");

    coordinator.offlineQueue.clear();

    coordinator.resume();
    expect(coordinator.isSuspended, isFalse);
    expect(coordinator.offlineQueue, contains("Background text"));

    coordinator.dispose();
  });

  test('TC-T4-05: ROI selection and cropping coordinates validation', () async {
    final mockHttpClient = MockClient((request) async {
      return http.Response('{"status": "success", "questions": ["summary"]}', 200);
    });
    final apiService = ApiService(httpClient: mockHttpClient, serverIp: '127.0.0.1', deviceId: 'test-device-id');
    final coordinator = PipelineCoordinator(
      captureService: captureService,
      ocrService: ocrService,
      apiService: apiService,
    );

    coordinator.roi = const Rect.fromLTWH(50, 100, 400, 300);
    ocrService.stubbedOutput = "Only this text";

    coordinator.start();
    await captureService.startCapture();

    simulateNativeFrame(Uint8List.fromList([1]));
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.apiUploads.first, contains("[ROI Cropped] Only this text"));

    coordinator.dispose();
  });

  test('TC-Pipeline-Concurrency: Frames dropped during concurrent processing', () async {
    final mockHttpClient = MockClient((request) async {
      return http.Response('{"status": "success", "questions": ["summary"]}', 200);
    });
    final apiService = ApiService(httpClient: mockHttpClient, serverIp: '127.0.0.1', deviceId: 'test-device-id');
    final delayingOcrService = DelayingMockOcrService(const Duration(milliseconds: 50));
    final coordinator = PipelineCoordinator(
      captureService: captureService,
      ocrService: delayingOcrService,
      apiService: apiService,
    );

    coordinator.start();
    await captureService.startCapture();

    // Send first frame: starts processing (takes 50ms)
    simulateNativeFrame(Uint8List.fromList([1, 2, 3]));
    // Send second frame immediately: should be dropped because first frame is still processing
    simulateNativeFrame(Uint8List.fromList([1, 2, 3]));

    // Wait for the first frame to complete
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(coordinator.framesProcessed, 1);
    expect(coordinator.eventLogs, contains("Frame dropped due to concurrent processing"));

    coordinator.dispose();
  });
}

class DelayingMockOcrService extends MockOcrService {
  final Duration delay;
  DelayingMockOcrService(this.delay);

  @override
  Future<String> recognizeText(Uint8List imageBytes, {Rect? roi}) async {
    await Future<void>.delayed(delay);
    return super.recognizeText(imageBytes, roi: roi);
  }
}
