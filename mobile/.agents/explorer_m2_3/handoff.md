# Handoff Report — Explorer M2_3

## 1. Observation

- **Backend Route Definition (`server/app.py` lines 30-55):**
  ```python
  @app.route('/extract', methods=['POST'])
  def extract_questions():
      # ...
      data = request.json
      chat_text = data.get('chat', '')
      # ...
      return jsonify({"questions": questions_list})
  ```
  The Flask server expects a payload containing a `chat` key and returns a JSON object with a `questions` key containing a list of strings (`questions_list`).

- **API Specification (`TEST_INFRA.md` lines 80-82 & 108-117):**
  ```dart
  abstract class IApiClient {
    Future<List<String>> extractQuestions(String chatText);
  }
  // ...
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
  The test specification aligns with the Flask server, returning a `Future<List<String>>` and utilizing the `'questions'` key.

- **Current API Client Implementation (`lib/services/api_service.dart` lines 6-8, 17-21, 37-44):**
  ```dart
  abstract class IApiService {
    Future<String> extractQuestions(String text);
  }
  // ...
  class ApiService implements IApiService {
    // ...
    @override
    Future<String> extractQuestions(String text) async {
      // ...
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        if (data['status'] == 'success') {
          return data['summary'] ?? '';
        } else {
          throw Exception('Failed status: ${data['status']}');
        }
      }
  ```
  The API service returns a `Future<String>` and expects the response JSON to contain `status` and `summary`.

- **Current API Test Implementation (`test/services/api_service_test.dart` lines 10-22):**
  ```dart
  test('TC-T1-F2-01: Successful Text Post', () async {
    final mockHttpClient = MockClient((request) async {
      return http.Response(
        jsonEncode({'status': 'success', 'summary': 'Question summary'}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final apiService = ApiService(httpClient: mockHttpClient, serverIp: '127.0.0.1');
    final result = await apiService.extractQuestions('Hello');
    expect(result, 'Question summary');
  });
  ```
  The test suite mocks the API to return the incorrect `{'status': 'success', 'summary': 'Question summary'}` payload to pass successfully.

---

## 2. Logic Chain

1. **Step 1:** The live Python Flask backend (`server/app.py`) defines the API response payload structure as `{"questions": [...]}` where the value is a list of strings, and expects requests to specify the chat text in the `'chat'` parameter.
2. **Step 2:** The `TEST_INFRA.md` specification mirrors this Flask API contract: it declares that `extractQuestions` returns a `Future<List<String>>` and describes `TC-T1-F2-04` as checking if a list of questions is parsed correctly.
3. **Step 3:** The mobile API service (`lib/services/api_service.dart`) implements `Future<String> extractQuestions(String text)` instead, posting a request but decoding the response expecting `{"status": "success", "summary": "..."}`.
4. **Step 4:** Due to the discrepancy in Step 3, the implementation will crash or throw an exception when connected to the live backend server from Step 1, since the server response has no `status` key.
5. **Step 5:** The unit tests in `test/services/api_service_test.dart` pass because they use a mock client returning the incorrect schema (`status` + `summary`), thereby masking the integration issue.

---

## 3. Caveats

- **Device ID Retrieval:** The exact mechanism to obtain the dynamic device ID on mobile (e.g. `device_info_plus`) was not investigated.
- **Pipeline Integration:** `PipelineCoordinator` currently ignores the returned type of `extractQuestions` other than verifying whether it succeeded or failed, meaning the mismatch does not crash the coordinator in isolation, but will crash it when a live server connection is used.

---

## 4. Conclusion

The implementation of Milestone 2 (Core API Client) is **functionally incorrect and incomplete** due to a fundamental API contract mismatch between the mobile client (`api_service.dart`) and the Flask backend (`server/app.py`), which is masked by matching incorrect mock schemas in the unit tests (`api_service_test.dart`).

To fix this:
1. Change `IApiService` to return `Future<List<String>>`.
2. Update `api_service.dart` to decode the response mapping `questions` and handle list conversion.
3. Rewrite the unit and integration tests to mock responses with the correct `questions` key.

---

## 5. Verification Method

To independently verify the contract differences and check the implementation correction, perform the following:
1. Inspect the Flask endpoint implementation in `d:\Projects\UniversalQAExtractor\server\app.py` around line 55:
   `return jsonify({"questions": questions_list})`
2. Inspect `d:\Projects\UniversalQAExtractor\mobile\lib\services\api_service.dart` around line 37-44 to confirm it checks `data['status'] == 'success'` and `data['summary']`.
3. Validate the proposed correction by running `flutter test test/services/api_service_test.dart` (after applying the changes in `analysis.md`). It should succeed with the updated mock payload matching `server/app.py`.
