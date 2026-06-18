# Test Infrastructure Recommendation Report: `TEST_INFRA.md`
**Date**: 2026-06-17T18:55:14Z  
**Author**: Explorer Subagent (Explorer 1)  
**Target File**: `d:\Projects\UniversalQAExtractor\mobile\TEST_INFRA.md`  

---

## 1. Executive Summary
This report outlines the recommended testing architecture and infrastructure design for the Universal QA Extractor Mobile application. The mobile app has three core features:
1. **F1**: Screen capture platform channel start/stop (controlling native iOS ReplayKit and Android MediaProjection).
2. **F2**: Local API transmission of extracted text (sending HTTP POSTs to `http://<YOUR_PC_IP>:5000/extract`).
3. **F3**: On-device OCR processing (interacting with Google MLKit).

To verify the app's business logic, state machines, and networking without requiring physical devices, we propose a mock-based test suite that executes via standard `flutter test` on the host development machine. By abstracting native bindings into mockable services and leveraging Flutter's platform channel interception APIs, we achieve 100% host-side verifiability with fast feedback loops.

---

## 2. Proposed Test Strategy and Architecture

### 2.1 Test Levels Taxonomy
To verify the features comprehensively without physical hardware, we structure tests across three layers:
*   **Unit Tests**: Validate business logic, text filtering, API response parsing, and state transitions. Direct dependencies (such as the HTTP client and OCR engine) are fully mocked.
*   **Widget & UI Tests**: Verify that the UI reflects system state changes (e.g., displaying "Capturing" vs "Idle", listing extracted questions, and showing network error dialogs).
*   **Mock E2E/Integration Tests**: Run the full application flow (Frame Capture -> OCR -> API Upload -> UI Update) on the host machine by linking mock components together via dependency injection.

### 2.2 Dependency Injection (DI) & Testability Architecture
To facilitate unit testing and mocking, the production code must avoid hardcoded class instantiation. We recommend constructor-based dependency injection or a service locator like `get_it`. 

```dart
// Dependency injection setup for the application
final locator = GetIt.instance;

void setupLocator({
  IOcrService? mockOcr,
  http.Client? mockHttpClient,
  MethodChannel? mockCaptureChannel,
}) {
  locator.registerLazySingleton<IOcrService>(() => mockOcr ?? MlKitOcrService());
  locator.registerLazySingleton<http.Client>(() => mockHttpClient ?? http.Client());
  // The screen capture controller uses the injected MethodChannel
}
```

---

## 3. Mocking Strategy Guide

### 3.1 Mocking MethodChannel (Screen Capture F1)
Flutter's `MethodChannel` communications can be intercepted during tests. We register mock handlers on the default binary messenger.

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void setupMockCaptureChannel() {
  const channel = MethodChannel('com.universalqaextractor.mobile/screen_capture');
  
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
    switch (methodCall.method) {
      case 'startCapture':
        // Simulates native side successfully starting capture
        return true;
      case 'stopCapture':
        // Simulates native side successfully stopping capture
        return true;
      case 'isCapturing':
        return true;
      default:
        throw PlatformException(
          code: 'UNSUPPORTED_METHOD',
          message: 'Method ${methodCall.method} not implemented',
        );
    }
  });
}
```

### 3.2 Mocking HTTP API Connections (F2)
Using `package:mocktail` or `package:mockito`, we mock the Dart `http.Client`. This allows us to inspect request parameters and inject success/failure responses.

```dart
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';

class MockHttpClient extends Mock implements http.Client {}

void testApiCall() {
  final mockClient = MockHttpClient();
  
  // Register fallback values for URI parameter matching
  registerFallbackValue(Uri());

  // Stub positive response
  when(() => mockClient.post(
    any(),
    headers: any(named: 'headers'),
    body: any(named: 'body'),
  )).thenAnswer((_) async => http.Response(
    '{"status": "success", "questions": ["What is MLKit?"]}', 
    200,
  ));
}
```

### 3.3 Mocking On-Device OCR Processing (F3)
Directly invoking Google MLKit in host tests throws `MissingPluginException` due to missing native libraries. We solve this by defining an abstract interface, `IOcrService`, wrapping MLKit. In tests, we inject a mock version of this service.

```dart
import 'dart:typed_data';
import 'package:mocktail/mocktail.dart';

abstract class IOcrService {
  Future<String> processFrame(Uint8List frameBytes, int width, int height);
}

class MockOcrService extends Mock implements IOcrService {}

void testOcrPipeline() {
  final mockOcr = MockOcrService();
  
  when(() => mockOcr.processFrame(any(), any(), any()))
      .thenAnswer((_) async => 'Moderator: Please type your questions here.');
}
```

---

## 4. Test Cases Catalog (38 Cases)

The test cases are partitioned across four tiers to guarantee thorough requirement coverage:
*   **Tier 1**: Functional Happy-Paths (15 cases, 5 per feature)
*   **Tier 2**: Boundary & Edge Cases (15 cases, 5 per feature)
*   **Tier 3**: Cross-Feature Interactions (3 cases)
*   **Tier 4**: Real-World Application Workloads (5 cases)

---

### Tier 1: Functional Happy-Path Tests (15 Cases)

#### Feature 1: Screen Capture Platform Channel Start/Stop (F1)

| Test ID | Test Name | Input / State | Action | Expected Output |
|---------|-----------|---------------|--------|-----------------|
| **TC-T1-F1-01** | Start Capture Success | Idle state | Call `startCapture()` on MethodChannel | Platform returns `true`, state becomes "capturing", UI displays active status. |
| **TC-T1-F1-02** | Stop Capture Success | Capturing state | Call `stopCapture()` on MethodChannel | Platform returns `true`, state becomes "idle", UI displays stopped status. |
| **TC-T1-F1-03** | Query Capture Status Active | Capturing state | Call `isCapturing()` on MethodChannel | Returns `true`. |
| **TC-T1-F1-04** | Query Capture Status Idle | Idle state | Call `isCapturing()` on MethodChannel | Returns `false`. |
| **TC-T1-F1-05** | Frame Buffer Streaming | EventChannel active | Platform posts image payload `[0x00, 0x01]` | UI/logic controller receives frame bytes and forwards to OCR module. |

#### Feature 2: Local API Transmission of Extracted Text (F2)

| Test ID | Test Name | Input / State | Action | Expected Output |
|---------|-----------|---------------|--------|-----------------|
| **TC-T1-F2-01** | Successful Text Post | Valid text input: "Hello" | Call `ApiService.sendExtractedText()` | HTTP status `200 OK` is returned, data parsed successfully. |
| **TC-T1-F2-02** | HTTP Request Headers | Standard request | Trigger API POST transmission | Outgoing request includes `Content-Type: application/json` header. |
| **TC-T1-F2-03** | JSON Body Encoding | Extracted chat text | Trigger API POST transmission | JSON payload contains correct keys (`text`, `timestamp`, `device_id`). |
| **TC-T1-F2-04** | Valid Response Parsing | Mock HTTP response payload | Invoke client API response parser | List of questions is correctly parsed and returned as domain objects. |
| **TC-T1-F2-05** | Base URL Dynamic Configuration | Configuration IP set to `192.168.1.5` | Instantiate/update ApiService | Outgoing request uses `http://192.168.1.5:5000/extract`. |

#### Feature 3: On-Device OCR Processing (F3)

| Test ID | Test Name | Input / State | Action | Expected Output |
|---------|-----------|---------------|--------|-----------------|
| **TC-T1-F3-01** | OCR Single Line Extraction | Image containing "Q1: What is Flutter?" | Invoke `OcrService.processFrame()` | Returns recognized string "Q1: What is Flutter?". |
| **TC-T1-F3-02** | OCR Empty Image Handling | Blank black image frame | Invoke `OcrService.processFrame()` | Returns empty string `""` without error. |
| **TC-T1-F3-03** | OCR Multi-line Sorting | Image with staggered top/bottom lines | Invoke `OcrService.processFrame()` | Returns combined text sorted in natural reading order (top-to-bottom). |
| **TC-T1-F3-04** | OCR Noise Filtering | Image with graphical noise | Invoke `OcrService.processFrame()` | Returns only recognized alphanumeric text; garbage symbols are omitted. |
| **TC-T1-F3-05** | OCR Region of Interest (ROI) | Full frame and bounding coordinates | Crop image and run OCR | Only text within the specified bounding box is recognized. |

---

### Tier 2: Boundary & Edge Case Tests (15 Cases)

#### Feature 1: Screen Capture Platform Channel Start/Stop (F1)

| Test ID | Test Name | Input / State | Action | Expected Output |
|---------|-----------|---------------|--------|-----------------|
| **TC-T2-F1-01** | Double Start Call Prevention | Capturing state | Call `startCapture()` again | Throws `AlreadyCapturingException` or returns `false` to prevent duplicate sessions. |
| **TC-T2-F1-02** | Double Stop Call Safety | Idle state | Call `stopCapture()` | Returns `true` or handles gracefully without modification of state or errors. |
| **TC-T2-F1-03** | OS Permission Denied | Permission rejected by user | Call `startCapture()` | Throws `PlatformException` with code `PERMISSION_DENIED`; app transitions to error UI. |
| **TC-T2-F1-04** | Platform Service Crash | Capturing state | Simulate platform service disconnection | App handles the channel disconnect exception, resets to "stopped" and logs error. |
| **TC-T2-F1-05** | Invalid Configuration Parameters | Zero resolution bounds (0x0) | Call `startCapture()` | Throws `ArgumentError` in Dart before reaching platform channel. |

#### Feature 2: Local API Transmission of Extracted Text (F2)

| Test ID | Test Name | Input / State | Action | Expected Output |
|---------|-----------|---------------|--------|-----------------|
| **TC-T2-F2-01** | Server Internal Error (500) | Valid text payload | Send POST; mock server returns 500 | ApiService returns failure code/result; UI prompts server error. |
| **TC-T2-F2-02** | Network Timeout | Connection delay exceeds threshold | Send POST; mock delay 10s | Client triggers `TimeoutException`, cancels request, and returns error. |
| **TC-T2-F2-03** | Host Unreachable | Wi-Fi down / invalid IP target | Send POST | Client triggers `SocketException`; app changes connectivity status to offline. |
| **TC-T2-F2-04** | Empty Payload Submission | Empty OCR result `""` | Attempt API transmission | ApiService short-circuits, returns success without sending actual HTTP request. |
| **TC-T2-F2-05** | Malformed JSON Response | Server returns invalid JSON text | Parse API response | Client throws `FormatException`; handled gracefully to prevent crash. |

#### Feature 3: On-Device OCR Processing (F3)

| Test ID | Test Name | Input / State | Action | Expected Output |
|---------|-----------|---------------|--------|-----------------|
| **TC-T2-F3-01** | Extremely Low Resolution Frame | Thumbnail image (50x50 pixels) | Run `OcrService.processFrame()` | Processes without error; returns empty or low-confidence match. |
| **TC-T2-F3-02** | Out of Memory (OOM) | High memory pressure | Invoke OCR analyzer | Native OOM exception caught in wrapper; returns failure status gracefully. |
| **TC-T2-F3-03** | Over-Dense Text Input | Frame with 5000+ characters | Run `OcrService.processFrame()` | OCR returns parsed text without crashing, potentially truncating past limit. |
| **TC-T2-F3-04** | Unsupported Image Format | Frame byte format invalid (e.g. RGB565) | Call frame processor | Throws `UnsupportedImageFormatException` in Dart validation layer. |
| **TC-T2-F3-05** | OCR Engine Model Not Ready | MLKit model downloading | Call `OcrService.processFrame()` | Throws custom `ModelNotReadyException`; system skips frames until model ready. |

---

### Tier 3: Cross-Feature Interaction Tests (3 Cases)

| Test ID | Test Name | Input / State | Action | Expected Output |
|---------|-----------|---------------|--------|-----------------|
| **TC-T3-01** | Complete End-to-End Pipeline | Capturing state, mock frame | Frame received -> OCR processes -> transmits text | HTTP POST request verified with exact text recognized from the mock frame. |
| **TC-T3-02** | OCR Failure Blocks API | Capturing state | Frame received -> OCR fails | API service is never invoked; system logs OCR failure. |
| **TC-T3-03** | Capture Stop Cancels API Queue | Active retries in queue | Call `stopCapture()` | Capture stops, and pending outgoing API requests/retries are immediately aborted. |

---

### Tier 4: Real-World Workload Tests (5 Cases)

| Test ID | Test Name | Input / State | Action | Expected Output |
|---------|-----------|---------------|--------|-----------------|
| **TC-T4-01** | Rapid Start/Stop Cycling | Idle state | Call `startCapture()` and `stopCapture()` 10 times in 2 seconds | System remains stable, resources cleaned up, final state matches final command. |
| **TC-T4-02** | Continuous High-Frequency Stream | Constant 30 FPS stream | Run capture pipeline | Rate-limiter restricts OCR processing to maximum 1 frame per second to save CPU/battery. |
| **TC-T4-03** | Flaky Network & Offline Queue | Intermittent internet connection | Send several OCR outputs | Failed transmissions are saved in local SQLite/in-memory queue and retried upon recovery. |
| **TC-T4-04** | Background Transition Throttle | App transitions to background | Call lifecycle pause event | OCR frequency is further reduced or paused entirely; foreground service notification active. |
| **TC-T4-05** | High-Load Frame Drop (LIFO) | OCR takes 800ms, frames arrive at 30ms | Feed continuous frames | Frame queue drops old pending frames and processes only the most recent one (LIFO). |

---

## 5. Implementation Recommendations and Next Steps

1.  **Define Interfaces**: Prior to writing mock tests, define interface classes (`IOcrService`, `IApiService`, `IScreenCaptureService`) in `lib/services/`.
2.  **Mock Library Selection**: Use `mocktail` for mocks as it provides a clean, modern API that does not require code generation (unlike Mockito).
3.  **Integrate with CI**: Add the testing command to the CI pipeline to run tests automatically.
4.  **Create Test Scaffolds**: Implement test files in `test/` following a structured layout matching the features:
    *   `test/services/ocr_service_test.dart`
    *   `test/services/api_service_test.dart`
    *   `test/services/screen_capture_test.dart`
    *   `test/pipeline_integration_test.dart`

### Verification Command
To run all tests and measure test coverage on the host system:
```bash
flutter test --coverage
```
The output coverage report should be located in `coverage/lcov.info`.
