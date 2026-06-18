# Milestone 2 Core API Client Analysis Report

## Summary
The Core API Client (`ApiService`) implementation and its unit tests are complete in terms of covering the required 10 Tier 1 and Tier 2 test cases from `TEST_INFRA.md`. However, they are functionally incorrect due to a major API contract mismatch: they use a custom response schema (`status` and `summary`) that is entirely incompatible with the actual Flask backend server (`server/app.py`) and the mock examples in `TEST_INFRA.md` which expect a list of questions (`questions`).

---

## 1. Evaluation of Implementation (`lib/services/api_service.dart`)

### A. Contract and Return Type Mismatch
* **Code Location:** `lib/services/api_service.dart` (lines 6-8, 17-21, 37-44)
* **Observation:**
  The implementation defines:
  ```dart
  abstract class IApiService {
    Future<String> extractQuestions(String text);
  }
  ```
  And processes the response as:
  ```dart
  if (response.statusCode == 200) {
    final Map<String, dynamic> data = jsonDecode(response.body);
    if (data['status'] == 'success') {
      return data['summary'] ?? '';
    } else {
      throw Exception('Failed status: ${data['status']}');
    }
  }
  ```
* **Issues:**
  1. **Flask Backend:** The actual Flask server (`server/app.py` line 55) returns `{"questions": questions_list}` (a list of strings) and has no `status` or `summary` keys.
  2. **Specification:** `TEST_INFRA.md` defines the interface as returning `Future<List<String>>` (lines 80-82) and specifies that the parser returns a "list of questions... as domain objects" (line 212).
  3. **Result:** Running the app against the real Flask backend will cause `ApiService` to throw `Exception: Failed status: null` because `status` is missing from the JSON.

### B. Payload Parameters
* **Code Location:** `lib/services/api_service.dart` (lines 29-34)
* **Observation:**
  ```dart
  body: jsonEncode({
    'text': text,
    'chat': text,
    'timestamp': DateTime.now().toIso8601String(),
    'device_id': 'mock-device-id',
  }),
  ```
* **Issues:**
  1. **Device ID:** The `device_id` is hardcoded as `'mock-device-id'`. For production usage, this should be dynamically injected (e.g., via constructor or device info service).
  2. **Flask Backend:** The backend reads the `chat` parameter (`data.get('chat', '')`). The client includes both `text` and `chat`, which satisfies the backend, but `text` is redundant.

---

## 2. Evaluation of Test Coverage (`test/services/api_service_test.dart`)

### A. Coverage Completeness
The unit test suite fully maps to the 10 required test cases listed in `TEST_INFRA.md` for Feature 2:
* **TC-T1-F2-01**: Successful Text Post (line 10)
* **TC-T1-F2-02**: HTTP Request Headers Validation (line 24)
* **TC-T1-F2-03**: JSON Body Encoding (line 38)
* **TC-T1-F2-04**: Valid Response Parsing (line 57)
* **TC-T1-F2-05**: Base URL Dynamic Configuration (line 71)
* **TC-T2-F2-01**: Server Internal Error (500) (line 85)
* **TC-T2-F2-02**: Network Timeout (line 97)
* **TC-T2-F2-03**: Host Unreachable (line 113)
* **TC-T2-F2-04**: Empty Payload Submission (line 125)
* **TC-T2-F2-05**: Malformed JSON Response (line 145)

### B. Coverage Correctness (The "Green Test" Fallacy)
* **Observation:**
  The tests mock the client responses using the incorrect `status` and `summary` schema. For instance, in `TC-T1-F2-01` (lines 11-16):
  ```dart
  final mockHttpClient = MockClient((request) async {
    return http.Response(
      jsonEncode({'status': 'success', 'summary': 'Question summary'}),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
  ```
* **Issues:**
  The tests all pass successfully, but they reinforce the incorrect assumptions. They do not validate the actual API payload returned by the Flask server or specified in `TEST_INFRA.md` (which returns a list of questions). This is a critical correctness gap.

---

## 3. Detailed Contract Discrepancy Table

| Feature / Aspect | Implementation (`api_service.dart`) | Backend Flask Server (`app.py`) | Test Infra Spec (`TEST_INFRA.md`) |
| --- | --- | --- | --- |
| **Interface Name** | `IApiService` | N/A | `IApiClient` |
| **Method Signature** | `Future<String> extractQuestions(String text)` | N/A | `Future<List<String>> extractQuestions(String chatText)` |
| **HTTP Request Path** | `/extract` (POST) | `/extract` (POST) | `/extract` (POST) |
| **Payload Keys** | `text`, `chat`, `timestamp`, `device_id` | `chat` | `chat`, `timestamp`, `device_id` |
| **Successful Response**| `{"status": "success", "summary": "..."}` | `{"questions": [...]}` | `{"questions": [...]}` |
| **Client Return Value**| `String` (containing summary text) | N/A | `List<String>` (containing questions) |

---

## 4. Integration Impact

In `lib/services/pipeline_coordinator.dart` (lines 64-71), the return value of `apiService.extractQuestions` is ignored (only checked for success/failure):
```dart
try {
  await apiService.extractQuestions(textToSend);
  apiUploads.add(textToSend);
  eventLogs.add("Successfully uploaded: $textToSend");
} catch (e) {
  offlineQueue.add(textToSend);
  eventLogs.add("Upload failed ($e); queued text: $textToSend");
}
```
Thus, the pipeline itself continues to work under the mock environment, but it will immediately break (throwing exceptions and dumping requests into the offline queue) when integrated with the live Flask backend.

---

## 5. Proposed Code Modifications

To align the client with the actual Flask backend and the `TEST_INFRA.md` specification, the following changes are proposed:

### Proposed Change to `lib/services/api_service.dart`

```dart
// 1. Change abstract interface signature
abstract class IApiService {
  Future<List<String>> extractQuestions(String text);
}

// 2. Modify ApiService implementation to return List<String> and parse 'questions'
class ApiService implements IApiService {
  final http.Client httpClient;
  final String serverIp;
  final String deviceId; // Dynamically inject device id

  ApiService({
    required this.httpClient, 
    required this.serverIp,
    this.deviceId = 'mock-device-id',
  });

  @override
  Future<List<String>> extractQuestions(String text) async {
    if (text.trim().isEmpty) {
      return [];
    }

    final Uri url = Uri.parse('http://$serverIp:5000/extract');
    
    try {
      final response = await httpClient.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'chat': text,
          'timestamp': DateTime.now().toIso8601String(),
          'device_id': deviceId,
        }),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        if (data.containsKey('questions')) {
          final List<dynamic> questions = data['questions'] is List 
              ? data['questions'] 
              : [data['questions']];
          return List<String>.from(questions);
        } else if (data.containsKey('error')) {
          throw Exception('Backend Error: ${data['error']}');
        } else {
          throw const FormatException('Missing questions in response');
        }
      } else if (response.statusCode == 500) {
        throw HttpException('Server Error: ${response.statusCode}');
      } else {
        throw HttpException('HTTP Error: ${response.statusCode}');
      }
    } on TimeoutException {
      rethrow;
    } on SocketException {
      rethrow;
    } on FormatException {
      rethrow;
    }
  }
}
```

### Proposed Change to `test/services/api_service_test.dart`

Update unit tests to verify the list structure returned by the API client:

```dart
  test('TC-T1-F2-01: Successful Text Post', () async {
    final mockHttpClient = MockClient((request) async {
      return http.Response(
        jsonEncode({'questions': ['Question 1', 'Question 2']}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final apiService = ApiService(httpClient: mockHttpClient, serverIp: '127.0.0.1');
    final result = await apiService.extractQuestions('Hello');
    expect(result, equals(['Question 1', 'Question 2']));
  });
```
(Apply equivalent changes to tests `TC-T1-F2-02`, `TC-T1-F2-03`, `TC-T1-F2-04`, `TC-T1-F2-05`, `TC-T2-F2-04`, `TC-T2-F2-05`, and integration tests in `pipeline_integration_test.dart`).
