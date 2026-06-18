# Handoff Report — Milestone 2: Core API Client Analysis

## 1. Observation
* **API Service File Path:** `d:\Projects\UniversalQAExtractor\mobile\lib\services\api_service.dart`
  - Defines the interface (lines 6-8):
    ```dart
    abstract class IApiService {
      Future<String> extractQuestions(String text);
    }
    ```
  - Sends payload keys `text`, `chat`, `timestamp`, `device_id` (lines 29-33):
    ```dart
    body: jsonEncode({
      'text': text,
      'chat': text,
      'timestamp': DateTime.now().toIso8601String(),
      'device_id': 'mock-device-id',
    }),
    ```
  - Parses response (lines 37-44):
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
  - Returns empty string on short-circuit (lines 19-21):
    ```dart
    if (text.trim().isEmpty) {
      return "";
    }
    ```

* **Flask Backend File Path:** `d:\Projects\UniversalQAExtractor\server\app.py`
  - Defines extraction endpoint and payload reading (lines 30-36):
    ```python
    @app.route('/extract', methods=['POST'])
    def extract_questions():
        ...
        data = request.json
        chat_text = data.get('chat', '')
    ```
  - Returns payload response (line 55):
    ```python
    return jsonify({"questions": questions_list})
    ```

* **Test Infrastructure File Path:** `d:\Projects\UniversalQAExtractor\mobile\TEST_INFRA.md`
  - Shows mock signature (lines 80-82):
    ```dart
    abstract class IApiClient {
      Future<List<String>> extractQuestions(String chatText);
    }
    ```
  - Happy path parser case (line 212) expected behavior: "List of questions is correctly parsed and returned as domain objects."
  - Empty payload case (line 243) expected behavior: "ApiService short-circuits locally, skips network request, and returns empty list."

* **Unit Test File Path:** `d:\Projects\UniversalQAExtractor\mobile\test\services\api_service_test.dart`
  - Uses mock clients containing `status` and `summary` (lines 11-16):
    ```dart
    final mockHttpClient = MockClient((request) async {
      return http.Response(
        jsonEncode({'status': 'success', 'summary': 'Question summary'}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    ```
  - Contains 10 test cases covering IDs `TC-T1-F2-01` to `TC-T2-F2-05`.

* **Pipeline Coordinator File Path:** `d:\Projects\UniversalQAExtractor\mobile\lib\services\pipeline_coordinator.dart`
  - Uses `IApiService` without consuming the return value (line 65):
    ```dart
    await apiService.extractQuestions(textToSend);
    ```

---

## 2. Logic Chain
1. **Response Contract Incompatibility:** Based on `app.py` (line 55), the backend returns `{"questions": questions_list}`. Based on `api_service.dart` (lines 37-44), the mobile client expects `{"status": "success", "summary": "..."}`. Since the response lacks the `status` field, the client will parse `data['status']` as `null` and throw `Exception: Failed status: null`.
2. **False Positive Testing (Green Test Fallacy):** Based on `api_service_test.dart`, all unit tests pass because they mock the client's custom schema (`{'status': 'success', 'summary': ...}`). The tests verify that the code behaves as written but fail to verify correctness against the actual backend server interface.
3. **Spec Deviation:** Based on `TEST_INFRA.md` (lines 80-82, 212, 243), the API client interface should return a list of questions (`Future<List<String>>`), and short-circuit empty inputs to an empty list `[]`. The actual implementation returns a `Future<String>` and short-circuits to `""`.
4. **Summary & Rationale:** Since the client will fail against the live backend and deviates from the `TEST_INFRA.md` specification, the current implementation is incomplete and incorrect.

---

## 3. Caveats
* **Network & Execution Testing:** Due to read-only constraints, no local tests were executed. The analysis relies on static review of the source code.
* **UI/Screen Capture:** The native capture service and OCR service are mock-verified but have not been evaluated for full live device interactions.

---

## 4. Conclusion
The implementation of the Core API Client in `lib/services/api_service.dart` and its test coverage in `test/services/api_service_test.dart` are **incorrect and incompatible with the live backend**. While tests pass, they suffer from the Green Test Fallacy (mocking the incorrect schema). Correcting this requires updating the client interface, response parsing logic, and corresponding test files to align with the list-based `{"questions": [...]}` contract of `server/app.py`.

---

## 5. Verification Method
To verify the analysis and future corrections:
1. Review the Flask server response structure in `server/app.py` (specifically line 55).
2. Run standard Flutter tests to verify that the mock tests compile and pass:
   ```powershell
   flutter test test/services/api_service_test.dart
   ```
3. To invalidate the bug findings, verify if there is any server middleware or API gateway that transforms the server output to `{"status": "success", "summary": "..."}`; no such middleware is present in this workspace.
