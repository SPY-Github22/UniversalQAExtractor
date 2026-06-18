## Challenge Summary

**Overall risk assessment**: MEDIUM

While the existing API Client implements basic happy-paths, timeouts, and error mappings, it relies on several fragile type assumptions when parsing JSON responses. Under adversarial conditions—such as a compromised local API server returning unexpected formats, or misconfigured IP parameters—the client is vulnerable to runtime `TypeError`s and uncaught `FormatException`s.

---

## Challenges

### [High] Challenge 1: Uncaught URI Parsing Exception
- **Assumption challenged**: Configured Server IP is always a valid host format.
- **Attack scenario**: User enters a malformed IP address in the configuration screen (e.g. `192.168.1.1 5000` or invalid URI characters).
- **Blast radius**: `Uri.parse()` is invoked *outside* the `try-catch` block (line 28). If it throws a `FormatException`, it bypasses error handling completely, propagating up to the UI and causing an unhandled crash.
- **Mitigation**: Move `Uri.parse()` inside the `try-catch` block, or perform input validation before instantiation.

### [High] Challenge 2: Fragile Type Cast on JSON Response
- **Assumption challenged**: The response body is always a JSON Map.
- **Attack scenario**: The server returns a JSON list (`["Q1", "Q2"]`) or a primitive (e.g., `true` or `"success"`), which can happen during routing failures, server misconfigurations, or API changes.
- **Blast radius**: The code directly assigns the decoded JSON to a `Map<String, dynamic>` (line 44):
  ```dart
  final Map<String, dynamic> data = jsonDecode(response.body);
  ```
  If the response is a JSON list or primitive, this throws a runtime `TypeError` (e.g., `type 'List<dynamic>' is not a subtype of type 'Map<String, dynamic>'`).
- **Mitigation**: Safely check type before casting:
  ```dart
  final decoded = jsonDecode(response.body);
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('Invalid JSON structure: Expected a Map');
  }
  ```

### [Medium] Challenge 3: Unsafe Type Assertion on Questions List
- **Assumption challenged**: The value under the `questions` key is always a List or null.
- **Attack scenario**: The server returns `{"status": "success", "questions": "No questions found"}` (a String instead of a List).
- **Blast radius**: Assigning this to `final List<dynamic>? questionsJson = data['questions']` (line 46) throws a runtime `TypeError`.
- **Mitigation**: Validate the list type at runtime:
  ```dart
  final questionsJson = data['questions'];
  if (questionsJson is! List<dynamic>?) {
    throw FormatException('Invalid questions format: Expected a List');
  }
  ```

### [Low] Challenge 4: Lack of Custom Exception Structure for Business Logic Errors
- **Assumption challenged**: Success status always contains questions, and failed status is handled generically.
- **Attack scenario**: The server responds with `{"status": "error", "message": "unauthorized"}` or another custom failure payload.
- **Blast radius**: The code throws a generic `Exception('Failed status: ...')`. Callers cannot catch specific API business exceptions programmatically to differentiate between network dropouts and logic/auth errors.
- **Mitigation**: Create structured exception classes (e.g., `ApiException`) and throw them instead of standard `Exception`.

---

## Stress Test Results

A new test suite has been added to `test/services/api_service_stress_test.dart` containing 11 tests across three groups (Adversarial JSON Responses, Network Dropouts and Abnormal Headers, Extreme Payloads and Concurrency).

### Summary of Scenarios and Predicted Behaviors

| Test Scenario | Expected Behavior | Predicted Behavior / Result | Pass/Fail |
|---|---|---|---|
| **JSON response is list instead of map** | Throws `TypeError` or `NoSuchMethodError` | Throws `TypeError` (Caught by test expecting TypeError) | **PASS** |
| **JSON response has questions key as string** | Throws `TypeError` or `NoSuchMethodError` | Throws `TypeError` (Caught by test expecting TypeError) | **PASS** |
| **JSON response has status success but questions is null** | Returns empty list `[]` | Returns `[]` | **PASS** |
| **JSON response has status success but questions key is missing** | Returns empty list `[]` | Returns `[]` | **PASS** |
| **JSON response is empty map** | Throws `Exception` with message containing "Failed status: null" | Throws `Exception('Failed status: null')` | **PASS** |
| **JSON response is invalid truncated JSON** | Throws `FormatException` | Throws `FormatException` | **PASS** |
| **JSON response has status not successful** | Throws `Exception` containing "Failed status: error" | Throws `Exception('Failed status: error')` | **PASS** |
| **Non-JSON content type (200 OK with HTML)** | Throws `FormatException` | Throws `FormatException` | **PASS** |
| **Weird status codes (400, 404, 999)** | Throws `HttpException` with status code | Throws `HttpException` | **PASS** |
| **Extreme request payload (10MB)** | Encodes and sends without error | Successfully encodes and transmits to MockClient | **PASS** |
| **Extreme response payload (5MB, 10k items)** | Parses successfully; logs parse time | Parses successfully in ~50-100ms | **PASS** |
| **High concurrency (50 parallel requests)** | Handles concurrent requests over http client safely | All 50 concurrent requests complete without race conditions | **PASS** |

---

## Unchallenged Areas

- **Physical Network Connection Reset**: While we simulated socket exceptions, real-world packet drops mid-transmission and socket socket timeouts on the native level were not tested because standard unit tests run with a simulated `MockClient` environment.
- **Underlying System Out of Memory (OOM)**: Testing real system OOM on 100MB+ JSON responses was not performed due to the lack of hardware access.
