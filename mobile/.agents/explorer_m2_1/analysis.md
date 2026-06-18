# Milestone 2: Core API Client Analysis Report (Synthesis)

## 1. Executive Summary
An investigation into the implementation of Milestone 2 (Core API Client) in `lib/services/api_service.dart` and its unit tests in `test/services/api_service_test.dart` reveals a critical API contract mismatch. While the client satisfies the 10 test cases in `TEST_INFRA.md` under simulated conditions, it is **incompatible with the actual Flask backend server** (`server/app.py`). 

The implementation expects a JSON response containing `status` and `summary` fields and returns a single `String`, whereas the Flask backend returns a `questions` field containing a list of strings (`List<String>`). Integrating the mobile client with the real backend will result in immediate execution failures (e.g., throwing a `Failed status: null` exception). 

---

## 2. Synthesis of Peer Analyses

### A. Catalog of Inputs
1. **Source 1 (`explorer_m2_2/analysis.md`)**: Assessed the implementation as complete and correct. Noted the return type mismatch (returns `String` instead of `List<String>`) but classified it as "low impact" because the internal mobile integration (`pipeline_coordinator.dart`) and unit tests were fully aligned on the `String` type.
2. **Source 2 (`explorer_m2_3/analysis.md`)**: Assessed the implementation as functionally incorrect. Noted that the client uses a custom response schema (`status`/`summary`) incompatible with `server/app.py` and `TEST_INFRA.md` (which use `questions`). Highlighted the "Green Test Fallacy" where unit/integration tests pass only because they assert against mock clients using the same incorrect schema.
3. **Source 3 (Our Investigation)**: Validated `server/app.py` (lines 35-55) and `extension/popup.js` (lines 44-73). Confirmed that the Flask backend expects `{chat: text}` as payload and returns `{"questions": [...]}`. Confirmed that the mobile client's implementation of `api_service.dart` will fail against the live backend.

### B. Consensus
All sources agree that:
- There is a mismatch between the return types: `api_service.dart` defines `IApiService` returning `Future<String>`, while `TEST_INFRA.md` specifies `Future<List<String>>` for `IApiClient`.
- The unit test suite in `api_service_test.dart` successfully covers all 10 test case IDs (`TC-T1-F2-01` through `TC-T2-F2-05`).

### C. Conflict Resolution
The primary conflict lies in the evaluation of correctness:
- `explorer_m2_2` evaluated the client as **correct** (high confidence) because it successfully builds, has 100% green tests, and integrates with the current mobile pipeline.
- `explorer_m2_3` evaluated the client as **incorrect** (high confidence) due to backend server incompatibility.

**Resolution (Evidence-Based)**: We adopt `explorer_m2_3`'s conclusion. Static analysis of the actual backend code (`server/app.py`, lines 35-55) confirms:
```python
@app.route('/extract', methods=['POST'])
def extract_questions():
    ...
    data = request.json
    chat_text = data.get('chat', '')
    ...
    questions_list = [q.strip() for q in extracted_questions.split('-') if q.strip()]
    ...
    return jsonify({"questions": questions_list})
```
Because `server/app.py` returns `{"questions": [...]}` and does not include `status` or `summary` keys, the mobile implementation's parsing logic (checking if `data['status'] == 'success'` and returning `data['summary']`) is functionally incorrect. It will fail with `Exception: Failed status: null` in any real-world scenario. The current "green status" of tests is a false positive caused by mocking the incorrect contract.

---

## 3. Detailed Contract Discrepancy Table

| Dimension | `TEST_INFRA.md` Specification | actual Flask Server (`app.py`) | Mobile Implementation (`api_service.dart`) |
| :--- | :--- | :--- | :--- |
| **Interface / Class** | `IApiClient` | N/A | `IApiService` |
| **Method Name** | `extractQuestions(String chatText)` | N/A | `extractQuestions(String text)` |
| **Request Payload** | `{'chat': chatText, 'timestamp': ..., 'device_id': ...}` | `{'chat': ...}` | `{'text': text, 'chat': text, 'timestamp': ..., 'device_id': 'mock-device-id'}` (includes redundant `text` key; hardcoded device ID) |
| **Response Format** | `{"questions": ["Q1", "Q2"]}` | `{"questions": ["Q1", "Q2"]}` | `{"status": "success", "summary": "..."}` |
| **Return Type** | `Future<List<String>>` | N/A | `Future<String>` |
| **Empty Payload** | Returns empty list `[]` (short-circuit) | Returns string message `{"questions": "No chat..."}` | Returns empty string `""` (short-circuit) |

---

## 4. Evaluation of Implementation (`lib/services/api_service.dart`)

1. **Response Schema Bug (Critical)**:
   Lines 37-44 check if `data['status'] == 'success'`. Since the live Flask backend never returns a `status` field, this check fails, causing the client to throw an exception and route all active transmissions into the offline cache queue.
2. **Payload Redundancy & Hardcoding (Minor)**:
   The request payload includes both `text` and `chat` keys. While the Flask backend only extracts `chat`, `text` is redundant. The `device_id` is hardcoded to `'mock-device-id'`. It should be dynamically retrieved or injected.
3. **URL Parameter Hardcoding (Minor)**:
   The constructor receives `serverIp` and hardcodes the URL structure as `http://$serverIp:5000/extract`. This is less robust than accepting a configurable base URL (e.g. supporting HTTPS, alternative ports, or custom routes).

---

## 5. Evaluation of Test Coverage (`test/services/api_service_test.dart`)

1. **Edge Case Alignment**:
   The test suite maps 1:1 to the 10 Feature 2 test IDs (`TC-T1-F2-01` to `TC-T2-F2-05`). It includes valid headers check, dynamic IP target, timeout limits (5s), SocketException handlers, malformed JSON FormatException handlers, and local empty/whitespace input short-circuiting.
2. **The Green Test Fallacy**:
   All tests pass successfully because they mock the client's custom schema rather than the actual server schema.
   - `TC-T1-F2-01` (lines 11-16) and `TC-T1-F2-04` (lines 57-69) return `jsonEncode({'status': 'success', 'summary': '...'})`.
   - `TC-T2-F2-04` asserts that short-circuiting returns `""`.
   The test suite confirms that the code operates as written, but fails to validate that the code is correct against the backend contract.

---

## 6. Pipeline Integration Impact (`lib/services/pipeline_coordinator.dart`)

The pipeline coordinator invokes the service as follows (lines 64-67):
```dart
try {
  await apiService.extractQuestions(textToSend);
  apiUploads.add(textToSend);
  eventLogs.add("Successfully uploaded: $textToSend");
} catch (e) {
  offlineQueue.add(textToSend);
  ...
}
```
Because it ignores the returned value and only awaits completion, the pipeline itself does not crash, but it immediately defaults to the offline/failure path due to the response parsing exception on the live server. Furthermore, in `TC-T4-05` (ROI selection verification, lines 277-300 in `pipeline_integration_test.dart`), it asserts:
```dart
expect(coordinator.apiUploads.first, contains("[ROI Cropped] Only this text"));
```
This demonstrates that the OCR text modification is verified, but the integration test mock client uses the wrong schema, masking the contract failure.

---

## 7. Proposed Structural and Code Changes

To resolve the discrepancy and ensure complete compatibility with the backend:

### A. Interface & Service Modifications (`lib/services/api_service.dart`)
```dart
abstract class IApiService {
  Future<List<String>> extractQuestions(String text);
}

class ApiService implements IApiService {
  final http.Client httpClient;
  final String serverIp;
  final String deviceId;

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
          final dynamic questionsData = data['questions'];
          if (questionsData is List) {
            return List<String>.from(questionsData);
          } else if (questionsData is String) {
            return [questionsData];
          }
          return [];
        } else if (data.containsKey('error')) {
          throw Exception('Backend Error: ${data['error']}');
        } else {
          throw const FormatException('Missing questions list in response');
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

### B. Unit Test Modifications (`test/services/api_service_test.dart`)
Modify the mocks to return the correct `{"questions": [...]}` payload, and assert lists:
```dart
  test('TC-T1-F2-01: Successful Text Post', () async {
    final mockHttpClient = MockClient((request) async {
      return http.Response(
        jsonEncode({'questions': ['What is E2E?', 'How does MLKit work?']}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final apiService = ApiService(httpClient: mockHttpClient, serverIp: '127.0.0.1');
    final result = await apiService.extractQuestions('Hello');
    expect(result, equals(['What is E2E?', 'How does MLKit work?']));
  });

  // Similarly update TC-T1-F2-04
  test('TC-T1-F2-04: Valid Response Parsing', () async {
    final mockHttpClient = MockClient((request) async {
      return http.Response(
        jsonEncode({'questions': ['Parsed Q1', 'Parsed Q2']}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final apiService = ApiService(httpClient: mockHttpClient, serverIp: '127.0.0.1');
    final result = await apiService.extractQuestions('Hello');
    expect(result, equals(['Parsed Q1', 'Parsed Q2']));
  });

  // Update TC-T2-F2-04 for empty payload
  test('TC-T2-F2-04: Empty Payload Submission', () async {
    int requestCount = 0;
    final mockHttpClient = MockClient((request) async {
      requestCount++;
      return http.Response(jsonEncode({'questions': []}), 200);
    });

    final apiService = ApiService(httpClient: mockHttpClient, serverIp: '127.0.0.1');
    final result1 = await apiService.extractQuestions('');
    final result2 = await apiService.extractQuestions('   ');

    expect(result1, isEmpty);
    expect(result2, isEmpty);
    expect(requestCount, 0);
  });
```

### C. Integration Test Modifications (`test/pipeline_integration_test.dart`)
All `MockClient` setup blocks in `pipeline_integration_test.dart` must be adjusted to return the correct schema:
```dart
    final mockHttpClient = MockClient((request) async {
      return http.Response(
        '{"questions": ["E2E summary"]}',
        200,
        headers: {'content-type': 'application/json'},
      );
    });
```
