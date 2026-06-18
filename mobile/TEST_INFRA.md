# E2E Test Infra: Universal QA Extractor Mobile

## Test Philosophy
- Opaque-box, requirement-driven. No dependency on implementation design.
- Methodology: Category-Partition + BVA + Pairwise + Workload Testing.

## Feature Inventory
| # | Feature | Source (requirement) | Tier 1 | Tier 2 | Tier 3 |
|---|---------|---------------------|:------:|:------:|:------:|
| 1 | F1: Screen capture platform channel | ORIGINAL_REQUEST §R2 | 5 | 5 | ✓ |
| 2 | F2: Local API transmission | ORIGINAL_REQUEST §R1 | 5 | 5 | ✓ |
| 3 | F3: On-device OCR processing | ORIGINAL_REQUEST §R2 | 5 | 5 | ✓ |

## Test Architecture
To enable automated execution in host environments (such as CI/CD pipelines) without relying on physical devices, Android Emulators, or iOS Simulators, the mobile client implements a **device-free test strategy**. All tests execute using standard host-side unit and widget test files (`flutter test`).

Hardware-dependent components (MediaProjection on Android, ReplayKit on iOS, local network adapter interfaces, and Google MLKit C++ binary libraries) are isolated using clean abstractions. During testing, mock implementations are injected via constructor dependency injection or service locator patterns.

### Mock Approaches

#### 1. Screen Capture Interception (F1)
Flutter uses a `MethodChannel` and `EventChannel` to communicate with the host operating system's native capture engine. In a test environment, these channels are intercepted using `setMockMethodCallHandler` on the binary messenger. Video frame streaming is simulated by encoding and pushing standard envelope packets through the binary messenger channel.

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
    
    // Register Mock Method Call Handler to intercept start/stop calls
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

  // Method to simulate native side pushing frame bytes (Uint8List) to Flutter
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

#### 2. API Transmission Mocking (F2)
Instead of using global HTTP requests directly, the transmission component injects an `http.Client`. In tests, a `MockClient` (from `package:http/testing.dart`) intercepts outgoing POST requests, verifies the payload structure, and returns mock response payloads (e.g. HTTP 200 OK or 500 error).

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

abstract class IApiClient {
  Future<List<String>> extractQuestions(String chatText);
}

class ApiService implements IApiClient {
  final http.Client httpClient;
  final String baseUrl;

  ApiService({required this.httpClient, required this.baseUrl});

  @override
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

// In unit and E2E tests, the custom MockClient is setup as follows:
final mockHttpClient = MockClient((request) async {
  if (request.url.path == '/extract') {
    return http.Response(
      jsonEncode({'questions': ['What is E2E?', 'How does MLKit work?']}),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
  return http.Response('Not Found', 404);
});
```

#### 3. OCR Processing Mocking (F3)
Directly referencing Google MLKit libraries causes host-side failures. To decouple the business logic from Google MLKit, an abstract `IOcrService` interface is implemented. During testing, a `MockOcrService` is injected to return predefined OCR strings for given image inputs without loading C++ libraries.

```dart
import 'dart:typed_data';

abstract class IOcrService {
  Future<String> recognizeText(Uint8List imageBytes);
}

class MlKitOcrService implements IOcrService {
  @override
  Future<String> recognizeText(Uint8List imageBytes) async {
    // Under test, this is bypassed by injecting MockOcrService.
    // Real implementation uses Google MLKit TextRecognizer on physical devices.
    throw UnimplementedError("MLKit requires running on a physical device/emulator.");
  }
}

class MockOcrService implements IOcrService {
  String stubbedOutput = "";
  bool shouldThrow = false;

  @override
  Future<String> recognizeText(Uint8List imageBytes) async {
    if (shouldThrow) {
      throw Exception("MLKit native failure");
    }
    return stubbedOutput;
  }
}
```

### Directory Layout
The tests are organized in a structured directory layout corresponding to each feature module and integrated pipelines:
- `test/services/screen_capture_test.dart`
- `test/services/api_service_test.dart`
- `test/services/ocr_service_test.dart`
- `test/pipeline_integration_test.dart`

---

## Real-World Application Scenarios (Tier 4)
These scenarios model realistic system-wide workloads and environmental challenges:

1. **Sustained Capture Leak Test (continuous streaming)**
   Simulates continuous screen capture and processing at 1 frame per second for an extended period (e.g. 10 minutes, representing 600 frames). Tests ensure that memory utilization remains flat, temporary frame buffers are correctly recycled, and no resource leaks occur in the OCR/API pipelines.

2. **Active Chat Scroll Duplicate Filter (overlapping text blocks)**
   Simulates a rapidly scrolling chat feed where consecutive captured frames contain large overlapping text blocks. Tests verify that the text-merging and deduping logic successfully appends only new chat lines, filtering out redundant/static lines to avoid making duplicate API calls.

3. **Offline Queueing and Reconnection Recovery (Wi-Fi toggle)**
   Simulates an active capture session while the local API server is unreachable. Verifies that extracted text is cached in an on-device SQLite database or memory queue. Once network connectivity is restored, the queue must automatically transmit the cached texts to the server.

4. **OS Suspension, Termination, and Re-initialization (app state cycle)**
   Simulates full lifecycle transitions where the app enters the background, gets terminated by the OS, and is subsequently re-opened. Verifies that capture buffers are cleaned up, the offline queue state is serialized, and the app resumes execution gracefully.

5. **Region of Interest (ROI) Cropping (bounding box selection)**
   Simulates selecting specific bounding box coordinates corresponding to the active chat box on a split screen. Verifies that only the cropped sub-image is passed to the OCR analyzer, preventing processing of unwanted background visual components.

---

## Coverage Thresholds
The test suite utilizes a strict tier-based verification approach to guarantee test coverage across all components:

- **Tier 1: Functional Happy-Path Tests** - 15 test cases (5 per feature)
- **Tier 2: Boundary & Edge Case Tests** - 15 test cases (5 per feature)
- **Tier 3: Cross-Feature Interaction Tests** - 3 test cases
- **Tier 4: Real-World Application Scenarios** - 5 test cases
- **Total Suite Coverage**: 38 test cases

---

## Complete Test Case Catalog

### Tier 1: Functional Happy-Path Tests (15 Cases)

#### F1: Screen capture platform channel
| Test ID | Test Name | Input/State | Action | Expected Output |
|---------|-----------|-------------|--------|-----------------|
| **TC-T1-F1-01** | Start Capture Success | Idle state | Call `startCapture()` on MethodChannel | Platform returns `true`, state becomes "capturing", and UI displays active status. |
| **TC-T1-F1-02** | Stop Capture Success | Capturing state | Call `stopCapture()` on MethodChannel | Platform returns `true`, state becomes "idle", and UI displays stopped status. |
| **TC-T1-F1-03** | Query Capture Status Active | Capturing state | Call `isCapturing()` on MethodChannel | Returns `true`. |
| **TC-T1-F1-04** | Query Capture Status Idle | Idle state | Call `isCapturing()` on MethodChannel | Returns `false`. |
| **TC-T1-F1-05** | Frame Buffer Streaming | EventChannel active | Platform posts image payload `[0x00, 0x01]` | Dart logic controller receives frame bytes and forwards to OCR module. |

#### F2: Local API transmission
| Test ID | Test Name | Input/State | Action | Expected Output |
|---------|-----------|-------------|--------|-----------------|
| **TC-T1-F2-01** | Successful Text Post | Valid text input: "Hello" | Call `ApiService.extractQuestions()` | HTTP status `200 OK` is returned, and questions are parsed successfully. |
| **TC-T1-F2-02** | HTTP Request Headers Validation | Standard request | Trigger API POST transmission | Outgoing request includes `Content-Type: application/json` header. |
| **TC-T1-F2-03** | JSON Body Encoding | Extracted chat text | Trigger API POST transmission | JSON payload contains correct keys (`chat`, `timestamp`, `device_id`). |
| **TC-T1-F2-04** | Valid Response Parsing | Mock HTTP response payload | Invoke client API response parser | List of questions is correctly parsed and returned as domain objects. |
| **TC-T1-F2-05** | Base URL Dynamic Configuration | Configuration IP set to `192.168.1.5` | Instantiate/update ApiService | Outgoing request endpoint target uses `http://192.168.1.5:5000/extract`. |

#### F3: On-device OCR processing
| Test ID | Test Name | Input/State | Action | Expected Output |
|---------|-----------|-------------|--------|-----------------|
| **TC-T1-F3-01** | OCR Single Line Extraction | Image containing "Q1: What is Flutter?" | Invoke `OcrService.recognizeText()` | Returns recognized string "Q1: What is Flutter?". |
| **TC-T1-F3-02** | OCR Empty Image Handling | Blank black image frame | Invoke `OcrService.recognizeText()` | Returns empty string `""` without errors or crashes. |
| **TC-T1-F3-03** | OCR Multi-line Sorting | Image with staggered top/bottom lines | Invoke `OcrService.recognizeText()` | Returns combined text sorted in natural reading order (top-to-bottom) preserving newlines. |
| **TC-T1-F3-04** | OCR Noise Filtering | Image with graphical noise | Invoke `OcrService.recognizeText()` | Returns only recognized alphanumeric text; garbage symbols are omitted. |
| **TC-T1-F3-05** | OCR Region of Interest (ROI) | Full frame and bounding coordinates | Crop image and run OCR | Only text within the specified bounding box coordinates is recognized. |

---

### Tier 2: Boundary & Edge Case Tests (15 Cases)

#### F1: Screen capture platform channel
| Test ID | Test Name | Input/State | Action | Expected Output |
|---------|-----------|-------------|--------|-----------------|
| **TC-T2-F1-01** | Double Start Call Prevention | Capturing state | Call `startCapture()` again | Request is ignored locally or native side returns `false` to prevent duplicate sessions. |
| **TC-T2-F1-02** | Double Stop Call Safety | Idle state | Call `stopCapture()` | Returns `true` or handles gracefully without modifying state or throwing errors. |
| **TC-T2-F1-03** | OS Permission Denied | Permission rejected by user | Call `startCapture()` | Throws `PlatformException` with code `PERMISSION_DENIED`; app transitions to error UI. |
| **TC-T2-F1-04** | Platform Service Crash / Disconnection | Capturing state | Simulate platform service disconnection | App handles the exception, resets to "idle"/"stopped", logs error, and notifies user. |
| **TC-T2-F1-05** | Invalid Configuration Parameters | Out-of-bounds coordinates (e.g. `[x: -10, y: -10]` or resolution `0x0`) | Call `startCapture()` | Throws `ArgumentError` or `PlatformException` in Dart validation layer before hitting channel. |

#### F2: Local API transmission
| Test ID | Test Name | Input/State | Action | Expected Output |
|---------|-----------|-------------|--------|-----------------|
| **TC-T2-F2-01** | Server Internal Error (500) | Valid text payload | Send POST; mock server returns 500 | ApiService returns failure code or throws server exception; UI prompts server error. |
| **TC-T2-F2-02** | Network Timeout | Connection delay exceeds threshold | Send POST; mock delay 10s | Client triggers `TimeoutException`, cancels request, and returns error. |
| **TC-T2-F2-03** | Host Unreachable | Wi-Fi down / invalid IP target | Send POST | Client triggers `SocketException`; app updates connectivity status. |
| **TC-T2-F2-04** | Empty Payload Submission | Empty OCR result `""` or whitespace `"   "` | Attempt API transmission | ApiService short-circuits locally, skips network request, and returns empty list. |
| **TC-T2-F2-05** | Malformed JSON Response | Server returns invalid JSON text | Parse API response | Client throws `FormatException`; handled gracefully to prevent crash. |

#### F3: On-device OCR processing
| Test ID | Test Name | Input/State | Action | Expected Output |
|---------|-----------|-------------|--------|-----------------|
| **TC-T2-F3-01** | Extremely Low Resolution Frame | Thumbnail image (e.g. 50x50 pixels) | Run `OcrService.recognizeText()` | Processes without error; returns empty or low-confidence match. |
| **TC-T2-F3-02** | Out of Memory (OOM) | High memory pressure | Invoke OCR analyzer | Native OOM exception caught in wrapper; returns failure status gracefully. |
| **TC-T2-F3-03** | Over-Dense Text Input | Frame with 5000+ characters | Run `OcrService.recognizeText()` | OCR returns parsed text without crashing, potentially truncating past limit. |
| **TC-T2-F3-04** | Unsupported Image Format | Frame byte format invalid (e.g. RGB565) | Call frame processor | Throws `UnsupportedImageFormatException` in Dart validation layer. |
| **TC-T2-F3-05** | OCR Engine Model Not Ready | MLKit model downloading | Call `OcrService.recognizeText()` | Throws custom `ModelNotReadyException`; system skips frames until model is ready. |

---

### Tier 3: Cross-Feature Interaction Tests (3 Cases)

| Test ID | Test Name | Input/State | Action | Expected Output |
|---------|-----------|-------------|--------|-----------------|
| **TC-T3-01** | Complete End-to-End Pipeline | Capturing state, mock frame | Frame received -> OCR processes -> transmits text | HTTP POST request verified with exact text recognized from mock frame; UI updates. |
| **TC-T3-02** | OCR Failure Blocks API | Capturing state | Frame received -> OCR fails | API service is never invoked; system logs OCR failure, and capture/pipeline stays active. |
| **TC-T3-03** | Capture Stop Cancels API Queue | Active retries in queue | Call `stopCapture()` | Capture stops, and pending outgoing API requests/retries are immediately aborted. |

---

### Tier 4: Real-World Application Scenarios (5 Cases)

| Test ID | Test Name | Input/State | Action | Expected Output |
|---------|-----------|-------------|--------|-----------------|
| **TC-T4-01** | Sustained Capture Leak Test | Continuous capture stream | Run capture loop for 10 minutes (600 frames at 1 FPS) | Stable memory usage (no leaks in OCR/HTTP); temp image buffers and native refs disposed. |
| **TC-T4-02** | Active Chat Scroll Duplicate Filter | Scrolling chat feed with overlapping text blocks | Process scrolling frame sequence | Only new chat lines are appended; redundant/static text is filtered, preventing duplicate requests. |
| **TC-T4-03** | Offline Queueing and Reconnection Recovery | Local API server offline | Toggle network during active capture | Failed transmissions are cached locally, then transmitted automatically when connection recovers. |
| **TC-T4-04** | OS Suspension, Termination, and Re-initialization | App state cycle | Trigger app background/suspension | Cleanly suspends native capture resources, serializes the offline queues, and resumes state cleanly. |
| **TC-T4-05** | Region of Interest (ROI) Cropping | Frame with split screen (chat + video) | Select crop region around active chatbox | OCR text output contains only chat logs, ignoring all text and visual artifacts in video region. |
