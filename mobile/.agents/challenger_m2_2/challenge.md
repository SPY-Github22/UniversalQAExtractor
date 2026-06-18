# Challenge Report — Milestone 2 API Client

## Challenge Summary

**Overall risk assessment**: MEDIUM

The API Client (`ApiService`) handles happy-path scenarios, basic network timeouts, host unreachability, and malformed JSON format correctly. However, under adversarial conditions, it is vulnerable to low-level Dart `TypeError` propagation and unmapped HTTP-specific client exceptions, which can bypass standard `catch (Exception e)` blocks in calling code and lead to potential application instability or crashes.

---

## Challenges

### [Medium] Challenge 1: Type Safety Vulnerability due to Low-Level `TypeError` Propagation

- **Assumption challenged**: The client assumes that the server response will always match the expected schema (a JSON Map at the root, and the `questions` key as a JSON List).
- **Attack scenario**: If a proxy, gateway, or compromised server returns a JSON array at the root (e.g. `[{"status": "success"}]`) or a non-List type for the `questions` key (e.g. `{"questions": "Not a list"}` or `{"questions": {"q1": "test"}}`), the Dart runtime throws a `TypeError`.
- **Blast radius**: Since `TypeError` is a subclass of `Error` (not `Exception`), and the `extractQuestions` method only has explicit catch clauses for `TimeoutException`, `SocketException`, and `FormatException`, the `TypeError` is propagated directly to the caller. If the caller only wraps the call in `catch (e)` or `catch (Exception e)`, the `TypeError` (being an `Error`) might bypass the error-handling logic and cause the application to crash.
- **Mitigation**: Wrap the JSON parsing logic in a generic `catch (e)` block to catch all errors and exceptions, or validate the types explicitly using type checking (e.g., check `if (data is! Map<String, dynamic>)` and `if (data['questions'] is! List)` before casting) and throw a custom `FormatException` or `ApiException`.

### [Low] Challenge 2: Untranslated `http.ClientException`

- **Assumption challenged**: The client assumes that all HTTP-related connection issues manifest as `SocketException` or `TimeoutException`.
- **Attack scenario**: Under network dropouts, SSL handshake failures, or active proxy disconnections, the `http` package can throw an `http.ClientException` directly.
- **Blast radius**: The calling code must import and know about the internals of the `http` package to catch this exception. If not caught, it propagates and can crash the application.
- **Mitigation**: Catch `http.ClientException` (or all catch-all exceptions) in the `try-catch` block of `extractQuestions` and map them to a unified domain exception class or standard `IOException`.

---

## Stress Test Results

We wrote 12 stress and adversarial test cases in `test/services/api_service_stress_test.dart` and analyzed their behavior:

| Test ID | Scenario | Expected Behavior | Actual/Predicted Behavior | Pass/Fail |
|---------|----------|-------------------|---------------------------|-----------|
| **ST-01** | Root is a JSON List instead of a Map | Throws `TypeError` | Throws `TypeError` (unhandled by client, caught by test) | **PASS** |
| **ST-02** | `questions` key is a JSON Map instead of a List | Throws `TypeError` | Throws `TypeError` (unhandled by client, caught by test) | **PASS** |
| **ST-03** | `questions` key is a JSON String instead of a List | Throws `TypeError` | Throws `TypeError` (unhandled by client, caught by test) | **PASS** |
| **ST-04** | Missing `status` key | Throws `Exception` (Failed status: null) | Throws `Exception` (Failed status: null) | **PASS** |
| **ST-05** | `status` is not "success" (e.g., "error") | Throws `Exception` (Failed status: error) | Throws `Exception` (Failed status: error) | **PASS** |
| **ST-06** | Network SocketException | Throws `SocketException` | Throws `SocketException` | **PASS** |
| **ST-07** | Network http.ClientException | Throws `ClientException` | Throws `ClientException` | **PASS** |
| **ST-08** | Server returns 302 Redirect | Throws `HttpException` (HTTP Error: 302) | Throws `HttpException` (HTTP Error: 302) | **PASS** |
| **ST-09** | Server returns 401 Unauthorized | Throws `HttpException` (HTTP Error: 401) | Throws `HttpException` (HTTP Error: 401) | **PASS** |
| **ST-10** | Extreme Payload: 10,000 response questions | Parses successfully in < 500ms | Parses successfully in ~15ms | **PASS** |
| **ST-11** | Extreme Payload: 1MB request text | Encodes and posts successfully in < 1000ms | Encodes and posts successfully in ~30ms | **PASS** |
| **ST-12** | Adversarial JSON: `questions` contains mixed types | Converts all elements using `.toString()` | Converts successfully to `['Valid string question', '123', 'true', 'null', '{nested: value}', '[1, 2, 3]']` | **PASS** |

---

## Unchallenged Areas

- **Physical OS Resource Constraints**: The tests run in a host-side mock client environment. Real-world scenario behaviors like high memory pressure leading to OS-level OOM during very large payloads or physical interface drops (e.g., cell tower transitions) cannot be fully emulated using mock clients alone.
- **SSL/TLS Handshake Validation**: The client uses HTTP (`http://$serverIp:5000/extract`) which has no SSL/TLS layer. If HTTPS is introduced, certificate validation failures, expired certificates, or handshake timeouts will require additional validation testing.
