# Universal QA Extractor Mobile - Test Infrastructure Design Recommendation

This document details the recommended test infrastructure design (`TEST_INFRA.md`) for the Universal QA Extractor Mobile app. The focus is to design an automated test strategy that allows E2E and unit verification without physical devices, relying on Flutter's test capabilities.

---

## 1. Test Strategy and Architecture

### 1.1 Device-Free Test Architecture
Flutter apps running on real devices communicate with native OS features (MediaProjection, ReplayKit, MLKit libraries, and network adapters). In a host-only environment (`flutter test`), these native components are unavailable. To achieve robust test coverage without physical devices, we propose an **interface-driven architecture**:

```
                       +----------------------+
                       |    UI / App State    |
                       +----------------------+
                                  |
            +---------------------+---------------------+
            |                     |                     |
            v                     v                     v
  +------------------+   +------------------+   +------------------+
  | IScreenCapture   |   |    IOcrEngine    |   |    IApiClient    |
  |    (Interface)   |   |    (Interface)   |   |    (Interface)   |
  +------------------+   +------------------+   +------------------+
            |                     |                     |
     +------+------+       +------+------+       +------+------+
     |             |       |             |       |             |
     v             v       v             v       v             v
+---------+  +---------+ +---------+ +---------+ +---------+ +---------+
| Native  |  |  Mock/  | |  MLKit  | |  Mock/  | |  Http   | |  Mock/  |
| Channel |  |  Fake   | |  Engine | |  Fake   | |  Client | |  Fake   |
| (Prod)  |  | (Tests) | |  (Prod) | | (Tests) | |  (Prod) | | (Tests) |
+---------+  +---------+ +---------+ +---------+ +---------+ +---------+
```

By decoupling features behind abstract interfaces, we can swap real implementations for mock or fake implementations at test-time using dependency injection (e.g., `get_it` or constructor injection).

### 1.2 Testing Strategy
- **Unit Tests**: Verify the parsing logic, IP validation, text block filtering, and error handling of `OcrService` and `ApiService` in isolation.
- **Widget/UI Tests**: Verify that buttons, status text, and lists respond correctly to state changes, simulated stream updates, and network errors.
- **Simulated E2E Tests**: Injecting fake/mock layers (`FakeScreenCapture`, `FakeOcrEngine`, and `MockClient`) to test the complete loop (Capture -> OCR -> API -> Display) as a single execution flow on the host machine.

---

## 2. How to Mock MethodChannel, HTTP API, and OCR

### 2.1 Mocking MethodChannel (F1)
Flutter uses `MethodChannel` for platform-specific interactions. During unit and widget tests, native code execution is bypassed. We register mock handlers on the platform channels via `defaultBinaryMessenger.setMockMethodCallHandler`.

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void setupMockScreenCaptureChannel() {
  const MethodChannel channel = MethodChannel('com.universalqa.extractor/screencapture');

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    channel,
    (MethodCall methodCall) async {
      switch (methodCall.method) {
        case 'startCapture':
          // Simulate native success or extract arguments
          final Map? args = methodCall.arguments as Map?;
          if (args != null && (args['width'] <= 0 || args['height'] <= 0)) {
            throw PlatformException(code: 'INVALID_COORDINATES', message: 'Bounds invalid');
          }
          return true;
        case 'stopCapture':
          return true;
        default:
          return null;
      }
    },
  );
}
```

### 2.2 Mocking HTTP API Connections (F2)
We isolate the HTTP transmission behind an `IApiClient` contract. Using the `http/testing` package or `mocktail/mockito`, we inject a `MockClient` to mock the Flask backend `/extract` endpoint responses.

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Interface
abstract class IApiClient {
  Future<List<String>> extractQuestions(String chatText);
}

// Mock Client Setup for Tests
IApiClient createMockApiClient({
  required int statusCode,
  required Map<String, dynamic> responseBody,
}) {
  final mockHttpClient = MockClient((request) async {
    return http.Response(
      jsonEncode(responseBody),
      statusCode,
      headers: {'content-type': 'application/json'},
    );
  });
  return ApiClientImpl(client: mockHttpClient, baseUrl: 'http://192.168.1.50:5000');
}
```

### 2.3 Mocking On-Device OCR Processing (F3)
MLKit's `google_mlkit_text_recognition` library requires a native binary. To mock this on host machines, we wrap it in an `IOcrEngine` interface and use a stubbed or fake engine in tests.

```dart
// Interface
abstract class IOcrEngine {
  Future<String> recognizeText(String imagePath);
}

// Stubbed implementation for testing
class FakeOcrEngine implements IOcrEngine {
  String textToReturn = "";
  bool shouldThrow = false;

  @override
  Future<String> recognizeText(String imagePath) async {
    if (shouldThrow) {
      throw Exception("OCR native engine failure");
    }
    return textToReturn;
  }
}
```

---

## 3. Detailed List of 38 Test Cases (Tiers 1-4)

### 3.1 Tier 1: Basic Functional Validation (15 cases)

#### Feature 1 (F1): Screen Capture Platform Channel Start/Stop
| ID | Title / Scenario | Input | Action | Expected Output |
|---|---|---|---|---|
| **1.1** | Start Capture Success | Coordinates `[x: 0, y: 0, w: 800, h: 600]` | Call `startCapture()` | Method returns `true`, state `isCapturing` becomes `true`. |
| **1.2** | Stop Capture Success | Active capture session (`isCapturing == true`) | Call `stopCapture()` | Method returns `true`, state `isCapturing` becomes `false`. |
| **1.3** | Get Active State | Active capture session | Query state `isCapturing` | Returns `true`. |
| **1.4** | Event Channel Listen | Active capture session | Subscribe to frame EventChannel | Receives simulated frame file paths sequentially. |
| **1.5** | Native Interruption Event | Active capture session | Platform sends interruption event | State `isCapturing` is set to `false`, UI notifies user. |

#### Feature 2 (F2): Local API Transmission
| ID | Title / Scenario | Input | Action | Expected Output |
|---|---|---|---|---|
| **1.6** | Successful Questions Extract | Chat text: `"User: What is E2E?"` | Call `apiClient.extractQuestions()` | Returns `["What is E2E?"]` parsed from HTTP 200 JSON. |
| **1.7** | Empty Chat Text Payload | Empty chat text `""` | Call `apiClient.extractQuestions()` | Skips HTTP request, returns empty list `[]`. |
| **1.8** | Server Error Response | Chat text: `"Hello"` | Server returns 500 error | Throws a custom `ServerException` containing error message. |
| **1.9** | Host IP Address Update | New IP address: `"192.168.1.10"` | Call `apiService.updateHostIp()` | Client updates endpoint to `http://192.168.1.10:5000/extract`. |
| **1.10**| Host Input Validation | Invalid IP string: `"abc.def"` | Set IP address | Validation throws `FormatException`, old host remains intact. |

#### Feature 3 (F3): On-Device OCR Processing
| ID | Title / Scenario | Input | Action | Expected Output |
|---|---|---|---|---|
| **1.11**| Extract Text from Image | Image path containing `"Hello"` | Call `ocrEngine.recognizeText()` | Returns string containing `"Hello"`. |
| **1.12**| Blank Image OCR | Image path containing blank canvas | Call `ocrEngine.recognizeText()` | Returns empty string `""` without crashing. |
| **1.13**| Multi-line Segment OCR | Image with multi-line layout | Call `ocrEngine.recognizeText()` | Returns multiline text preserving newlines. |
| **1.14**| OCR Engine Init | App startup | Instantiate `OcrService` | Status `isInitialized` is `true`, engine is ready. |
| **1.15**| OCR Resource Release | Active OCR session | Call `ocrService.dispose()` | Native engine is shut down, memory freed. |

---

### 3.2 Tier 2: Boundary & Corner Cases (15 cases)

#### Feature 1 (F1): Screen Capture Platform Channel Start/Stop
| ID | Title / Scenario | Input | Action | Expected Output |
|---|---|---|---|---|
| **2.1** | Re-entrant Start Call | Capturing already running | Call `startCapture()` again | Request is ignored or returns `false`, preventing double launch. |
| **2.2** | Negative Coordinates | Out-of-bounds coordinates `[x:-10, y:-10]` | Call `startCapture()` | Throws `PlatformException` or validation error. |
| **2.3** | Permission Denial | User cancels permission dialog | Call `startCapture()` | Native returns exception, state remains `isCapturing == false`. |
| **2.4** | Stop Capture when Idle | Capturing is inactive | Call `stopCapture()` | Returns `false` or completes silently without crashing. |
| **2.5** | Native Process Death | Active capture session | Simulate sudden platform stream close | State changes to `isCapturing = false`, UI shows error toast. |

#### Feature 2 (F2): Local API Transmission
| ID | Title / Scenario | Input | Action | Expected Output |
|---|---|---|---|---|
| **2.6** | Host Unreachable | Correct IP, local server not running | Call `apiClient.extractQuestions()` | Throws `SocketException` (wrapped as `NetworkException`). |
| **2.7** | Request Timeout | Server takes > 10s to respond | Call `apiClient.extractQuestions()` | Request times out at 5s, throws `TimeoutException`. |
| **2.8** | Malformed JSON Payload | Server returns HTTP 200, invalid JSON | Call `apiClient.extractQuestions()` | Throws `FormatException` during response parsing. |
| **2.9** | IP Address Hostname Port | URL with custom port: `"192.168.1.5:8080"` | Update server address | Host configuration parsed correctly, requests sent to port `8080`. |
| **2.10**| Gigantic Text Payload | Chat block size 1MB (500k+ chars) | Call `apiClient.extractQuestions()` | Sends payload successfully without out-of-memory crash. |

#### Feature 3 (F3): On-Device OCR Processing
| ID | Title / Scenario | Input | Action | Expected Output |
|---|---|---|---|---|
| **2.11**| Missing Image File | Invalid path: `"/nonexistent.png"` | Call `ocrEngine.recognizeText()` | Throws `FileNotFoundException` or similar wrapper error. |
| **2.12**| Corrupted Image Data | Exists but has corrupted bytes | Call `ocrEngine.recognizeText()` | Throws image decoding error, handled gracefully. |
| **2.13**| Low-Contrast Frame OCR | Very blurry or dark text image | Call `ocrEngine.recognizeText()` | Returns empty or partial match; does not crash. |
| **2.14**| Complex Unicode / Emojis | Frame contains emojis and symbols | Call `ocrEngine.recognizeText()` | Extracts alphanumeric matches, handles emojis without errors. |
| **2.15**| Extreme Aspect Ratio | Narrow image `[w: 10, h: 4000]` | Call `ocrEngine.recognizeText()` | Processes layout safely without memory leaks or crashes. |

---

### 3.3 Tier 3: Cross-Feature Interactions (3 cases)

| ID | Title / Scenario | Input | Action | Expected Output |
|---|---|---|---|---|
| **3.1** | End-to-End Extraction Loop | Mock image sequence + HTTP Mock | Start capture, feed images, mock API 200 | Stream delivers images, OCR converts to text, API extracts questions, UI list updates. |
| **3.2** | API Failure Resilience | Mock image sequence + HTTP Mock 500 | Start capture, feed images, API returns 500 | Pipeline logs error, updates connection status to "Warning", but capture/OCR stays active. |
| **3.3** | Immediate Stop Cleanup | Active queue of 10 frame tasks | Trigger `stopCapture()` midway | Capture stops, pending OCR and API tasks are cancelled, queues cleared. |

---

### 3.4 Tier 4: Real-World Workloads (5 cases)

| ID | Title / Scenario | Input | Action | Expected Output |
|---|---|---|---|---|
| **4.1** | 1-Hour Stream Endurance | 3,600 simulated frames (1 per second) | Run capture loop for 1 hour | Stable memory usage (no leaks in OCR/HTTP), UI remains highly responsive. |
| **4.2** | High-Frequency Frame Drops | Native feeds frames at 60 FPS | Stream frames at 60 FPS | Backpressure logic drops older frames, processing only latest frame. No queue buildup. |
| **4.3** | Intermittent Network Outage | Active loop, toggle WiFi off then on | Toggle connection during loop | API requests fail/queued, then resume succeeding automatically once link restores. |
| **4.4** | App State Transitions | Active capture, minimize app | Change LifecycleState to paused | Native capture continues in background if permitted, or pauses/resumes state cleanly. |
| **4.5** | Dense Rapid Chat Stream | Fast scrolling high-volume chat | Process dense chat sequence | OCR extracts text blocks, API transmits large payload, returns parsed list, UI loads without lag. |
