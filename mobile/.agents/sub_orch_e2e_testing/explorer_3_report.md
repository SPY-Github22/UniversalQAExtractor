# Recommendation Report: Mobile Test Infrastructure Design (`TEST_INFRA.md`)

## Executive Summary
This report recommends the design of the E2E and integration test infrastructure for the Universal QA Extractor Mobile app. To allow testing without physical devices and enable full automation in CI/CD pipelines, this architecture employs Dart-level abstractions and mock injection for `MethodChannel`, `http.Client`, and `google_mlkit_text_recognition`. A suite of 38 test cases is defined across Tiers 1-4 to ensure high reliability across all features.

---

## 1. Proposed Test Strategy & Architecture

### Objectives
* **Device-Free Execution**: Run all tests via `flutter test` on standard development machines or CI/CD runner nodes (e.g., GitHub Actions) without needing physical devices, Android Emulators, or iOS Simulators.
* **Hermetic and Deterministic Tests**: Eliminate external network calls and hardware dependencies, making test outcomes fully reproducible and fast.
* **Component-Level Isolation**: Ensure each core feature (Screen Capture, API Transmission, OCR) can be tested in isolation as well as in integrated scenarios.

### Architectural Blueprint
```
+-------------------------------------------------------------+
|                        Flutter Test                         |
+-------------------------------------------------------------+
                               |
                               v
+-------------------------------------------------------------+
|                      Test Environment                       |
|  - MockMethodChannel (Simulates MediaProjection/ReplayKit)   |
|  - MockClient (Simulates Python REST API server)            |
|  - MockOcrService (Simulates Google MLKit OCR Text)         |
+-------------------------------------------------------------+
                               |
                               v
+-------------------------------------------------------------+
|                      Mobile App Core                        |
|  - CaptureController (Controls start/stop & event stream)   |
|  - ApiService (Sends extracted text to local backend)       |
|  - OcrService (Converts image frames to plain text)         |
+-------------------------------------------------------------+
```

---

## 2. Mocking Guidelines & Technical Implementations

### A. Mocking Feature 1: Screen Capture (`MethodChannel` & `EventChannel`)
Flutter's platform channels must be intercepted at the binary messenger level during tests.

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class MockCaptureChannel {
  static const MethodChannel methodChannel = MethodChannel('com.universalqa.extractor/screen_capture');
  static const EventChannel eventChannel = EventChannel('com.universalqa.extractor/frame_stream');

  final List<MethodCall> methodCallLog = <MethodCall>[];
  bool isCapturing = false;

  void initialize() {
    TestWidgetsFlutterBinding.ensureInitialized();
    
    // Register Mock Method Call Handler
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, (MethodCall methodCall) async {
      methodCallLog.add(methodCall);
      switch (methodCall.method) {
        case 'startCapture':
          isCapturing = true;
          return true;
        case 'stopCapture':
          isCapturing = false;
          return true;
        case 'isCapturing':
          return isCapturing;
        default:
          return null;
      }
    });
  }

  // Method to simulate native side pushing a video frame (Uint8List) to Flutter
  void simulateNativeFrame(Uint8List frameData) {
    const StandardMethodCodec codec = StandardMethodCodec();
    final ByteData message = codec.encodeSuccessEnvelope(frameData);
    
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      'com.universalqa.extractor/frame_stream',
      message,
      (ByteData? reply) {},
    );
  }
}
```

### B. Mocking Feature 2: Local API Transmission (`http.Client`)
Using dependency injection, we pass a mocked client to `ApiService` instead of using the global `http` singleton.

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class ApiService {
  final http.Client httpClient;
  final String baseUrl;

  ApiService({required this.httpClient, required this.baseUrl});

  Future<List<String>> extractQuestions(String chatText) async {
    final response = await httpClient.post(
      Uri.parse('$baseUrl/extract'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'chat': chatText}),
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = jsonDecode(response.body);
      return List<String>.from(data['questions']);
    } else {
      throw Exception('Server error: ${response.statusCode}');
    }
  }
}

// In-test setup:
// final mockClient = MockClient((request) async {
//   return http.Response(jsonEncode({'questions': ['Q1', 'Q2']}), 200);
// });
// final apiService = ApiService(httpClient: mockClient, baseUrl: 'http://192.168.1.100:5000');
```

### C. Mocking Feature 3: On-Device OCR Processing (`google_mlkit_text_recognition`)
Since `google_mlkit_text_recognition` depends on native binary libraries, we wrap its usage in an abstract interface that can be easily mocked.

```dart
import 'dart:io';

abstract class OcrService {
  Future<String> recognizeText(File imageFile);
}

class MlKitOcrService implements OcrService {
  // Real implementation wrapping MLKit
  @override
  Future<String> recognizeText(File imageFile) async {
    // Under test, this line is avoided by injecting MockOcrService instead
    throw UnimplementedError("MLKit requires running on a physical device/emulator.");
  }
}

// In-test Mock Implementation
class MockOcrService implements OcrService {
  String stubbedOutput = "";
  bool shouldThrow = false;

  @override
  Future<String> recognizeText(File imageFile) async {
    if (shouldThrow) {
      throw Exception("MLKit native failure");
    }
    return stubbedOutput;
  }
}
```

---

## 3. Test Cases (38 Cases Partitioned Across Tiers 1-4)

### Tier 1: Unit & Component Tests (Sanity/Happy Path) - 15 Cases

#### F1: Screen capture platform channel start/stop
* **TC-1**: Channel initialization
  * **Input**: Test app bootstrap.
  * **Action**: Instantiate the capture controller.
  * **Expected Output**: Platform channel handles are successfully bound.
* **TC-2**: Successful `startCapture` invocation
  * **Input**: Request to start capture.
  * **Action**: Call `CaptureController.start()`.
  * **Expected Output**: Invokes `startCapture` on `MethodChannel`; returns `true`; status is `capturing`.
* **TC-3**: Successful `stopCapture` invocation
  * **Input**: Request to stop capture.
  * **Action**: Call `CaptureController.stop()`.
  * **Expected Output**: Invokes `stopCapture` on `MethodChannel`; returns `true`; status is `idle`.
* **TC-4**: Frame callback stream binding
  * **Input**: An active stream callback registered in Dart.
  * **Action**: Simulate a native frame event using mock binary messenger.
  * **Expected Output**: Dart callback is invoked with the raw frame bytes (`Uint8List`).
* **TC-5**: State query reporting
  * **Input**: Request capture state.
  * **Action**: Check `CaptureController.isCapturing`.
  * **Expected Output**: Returns `true` if capture is active, `false` otherwise.

#### F2: Local API transmission of extracted text
* **TC-6**: Successful network transaction
  * **Input**: Clean text string: "Hello, what is the answer?".
  * **Action**: Call `ApiService.extractQuestions()`.
  * **Expected Output**: Mock server receives POST; returns `200 OK`; parsed list is `["what is the answer?"]`.
* **TC-7**: Request headers validation
  * **Input**: Extraction request.
  * **Action**: Inspect headers sent by `ApiService`.
  * **Expected Output**: Header map contains `Content-Type: application/json`.
* **TC-8**: Empty question list handling
  * **Input**: Mock response payload: `{"questions": []}`.
  * **Action**: Call `ApiService.extractQuestions()`.
  * **Expected Output**: Returns empty Dart `List<String>`.
* **TC-9**: Multi-question payload parsing
  * **Input**: Mock response payload: `{"questions": ["Q1", "Q2", "Q3"]}`.
  * **Action**: Call `ApiService.extractQuestions()`.
  * **Expected Output**: Returns `["Q1", "Q2", "Q3"]`.
* **TC-10**: Payload JSON structuring
  * **Input**: String input "Text to send".
  * **Action**: Inspect POST request body.
  * **Expected Output**: Body is exactly `{"chat": "Text to send"}`.

#### F3: On-device OCR processing
* **TC-11**: Normal text extraction
  * **Input**: Reference mock image file path.
  * **Action**: Call `OcrService.recognizeText()`.
  * **Expected Output**: Returns stubbed extracted text block successfully.
* **TC-12**: Blank image input
  * **Input**: File path representing a completely blank image.
  * **Action**: Call `OcrService.recognizeText()` with empty stub set.
  * **Expected Output**: Returns empty string `""` (no crash).
* **TC-13**: Multiline formatting conversion
  * **Input**: Mock image with separate text blocks at different vertical coordinates.
  * **Action**: Process image and check layout ordering.
  * **Expected Output**: Blocks are returned separated by newline characters `\n` in reading order.
* **TC-14**: Clean OCR engine instantiation
  * **Input**: Create an OCR Service.
  * **Action**: Instantiate `MlKitOcrService`.
  * **Expected Output**: Object is instantiated without throwing runtime exceptions.
* **TC-15**: Special character preservation
  * **Input**: Image containing standard symbols like `?`, `-`, and `:`.
  * **Action**: Process image in OCR service.
  * **Expected Output**: Punctuation is preserved in the output string.

---

### Tier 2: Boundary & Corner Cases - 15 Cases

#### F1: Screen capture platform channel start/stop
* **TC-16**: Duplicate start call protection
  * **Input**: Calling `CaptureController.start()` while status is already `capturing`.
  * **Action**: Call start twice consecutively.
  * **Expected Output**: Service rejects second invocation locally or native side returns false; does not re-register handlers.
* **TC-17**: Duplicate stop call handling
  * **Input**: Calling `CaptureController.stop()` while status is already `idle`.
  * **Action**: Call stop twice.
  * **Expected Output**: Service gracefully returns false, does not throw an exception.
* **TC-18**: Native Permission Denied handler
  * **Input**: User clicks "Deny" on native MediaProjection/ReplayKit dialog.
  * **Action**: `MethodChannel` throws `PlatformException('PERMISSION_DENIED', ... )`.
  * **Expected Output**: App catches exception, resets capture state, and updates UI to display a user warning.
* **TC-19**: Sudden native connection termination
  * **Input**: Active EventChannel stream.
  * **Action**: Simulate native side emitting stream error or closing without notice.
  * **Expected Output**: Capture is cleaned up, state switches to `idle`, and app alerts the user of a platform error.
* **TC-20**: App lifecycle suspension behavior
  * **Input**: Lifecycle transition to background state.
  * **Action**: Send `AppLifecycleState.paused` notification.
  * **Expected Output**: Capture is stopped or paused, release native assets, and save state.

#### F2: Local API transmission of extracted text
* **TC-21**: Backend Server Offline
  * **Input**: Post request while target IP is unreachable.
  * **Action**: HttpClient throws `SocketException` or `TimeoutException`.
  * **Expected Output**: Service catches the error and reports connection failure status.
* **TC-22**: Server 500 error propagation
  * **Input**: Mock server returns `500 Internal Server Error` with `{"error": "Model not trained yet"}`.
  * **Action**: Call `ApiService.extractQuestions()`.
  * **Expected Output**: App catches error and exposes the internal error message to UI handlers.
* **TC-23**: Malformed JSON response
  * **Input**: Mock server returns raw text string "Internal Error" instead of valid JSON.
  * **Action**: Invoke api call.
  * **Expected Output**: Catches `FormatException`, handles gracefully, returns custom parsing error.
* **TC-24**: Extremely large text transmission
  * **Input**: Extracted chat history string exceeding 100,000 characters.
  * **Action**: Invoke `ApiService.extractQuestions()`.
  * **Expected Output**: App safely encodes and sends payload without out-of-memory or stack overflow issues.
* **TC-25**: Empty or whitespace-only transmission
  * **Input**: Whitespace-only string `"   "`.
  * **Action**: Call `ApiService.extractQuestions()`.
  * **Expected Output**: API client intercepts request locally, cancels network transaction, and returns empty list.

#### F3: On-device OCR processing
* **TC-26**: Low confidence detection threshold
  * **Input**: Mock OCR results containing block elements with low confidence (< 0.35).
  * **Action**: Filter and extract.
  * **Expected Output**: Low confidence text blocks are excluded from the merged output string.
* **TC-27**: Non-ASCII and Emoji filtering
  * **Input**: Mock image containing non-Latin characters and emoji icons.
  * **Action**: Process image.
  * **Expected Output**: Text is correctly read as UTF-8; emoji blocks are ignored or handled gracefully without crashing.
* **TC-28**: High-resolution frame downscaling
  * **Input**: A 4K video frame image.
  * **Action**: Submit to `OcrService`.
  * **Expected Output**: Service automatically downscales image dimensions to a standard processing resolution to avoid memory overflow.
* **TC-29**: Corrupted or empty image file
  * **Input**: A file reference containing 0 bytes.
  * **Action**: Submit to `OcrService`.
  * **Expected Output**: Service rejects the file locally with an `ArgumentException` and does not invoke native library.
* **TC-30**: Concurrent frame processing guard
  * **Input**: Three frames arrive in rapid succession (< 50ms intervals).
  * **Action**: Submit to `OcrService`.
  * **Expected Output**: Service serializes requests or drops stale frames, processing only one frame at a time.

---

### Tier 3: Integration / Cross-Feature Interactions - 3 Cases

* **TC-31**: Screen Capture to OCR pipeline
  * **Input**: Start capture; trigger native frame event.
  * **Action**: Feed the resulting frame bytes from the stream directly into the OCR processor.
  * **Expected Output**: Bytes are parsed, an image structure is built, and text is extracted.
* **TC-32**: OCR to API pipeline
  * **Input**: Simulated raw frame containing a chat bubble.
  * **Action**: Pass frame to OCR; take the output string and call the API service.
  * **Expected Output**: OCR returns text, and API service receives that exact text as the request payload and parses the output questions.
* **TC-33**: Full System Loop Integration
  * **Input**: Start capture -> generate frame -> run OCR -> call API.
  * **Action**: Run complete pipeline mock-to-mock.
  * **Expected Output**: Pipeline executes from start to end; questions are successfully saved and state is updated.

---

### Tier 4: System / Real-World Workloads - 5 Cases

* **TC-34**: Sustained Capture Leak Test
  * **Input**: Continuous capture and processing stream at 1 frame per second for 10 minutes (600 frames).
  * **Action**: Run loop.
  * **Expected Output**: Memory usage remains flat; temp image buffers and native references are disposed after every frame.
* **TC-35**: Active Chat Scroll Duplicate Filter
  * **Input**: Multiple consecutive frames representing a scrolling chat feed with overlapping text blocks.
  * **Action**: Process frames and run delta-merging logic.
  * **Expected Output**: Only new chat lines are appended; redundant/static text is filtered, preventing duplicate question requests to the API.
* **TC-36**: Offline Queueing and Reconnection Recovery
  * **Input**: Active capture producing text while the local API server is offline, then becomes online.
  * **Action**: Simulate network disconnect, collect text, simulate reconnect.
  * **Expected Output**: Extracted text blocks are queued locally during offline state and transmitted automatically when connection is re-established.
* **TC-37**: OS Suspension, Termination, and Re-initialization
  * **Input**: Capture in progress -> App enters background -> App is force-stopped -> App is re-opened.
  * **Action**: Simulate standard lifecycle events and state serialization.
  * **Expected Output**: App cleanly terminates capture resources, serializes the offline queues, and resumes with a clean state upon restart.
* **TC-38**: Region of Interest (ROI) Cropping
  * **Input**: Full-screen frame containing a chat pane on the right-hand side and video content on the left.
  * **Action**: Crop coordinates corresponding to the active chat box before running OCR.
  * **Expected Output**: OCR text output contains only chat logs, ignoring all text and visual artifacts present in the video region.
