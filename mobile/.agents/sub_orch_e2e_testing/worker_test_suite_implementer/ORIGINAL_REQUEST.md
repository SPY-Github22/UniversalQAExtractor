## 2026-06-18T01:17:21+05:30
You are a Worker subagent for the E2E Testing Track.
Task: Implement the E2E and unit test files for the Universal QA Extractor Mobile application under `d:\Projects\UniversalQAExtractor\mobile\test/`.
Create the following 4 test files containing exactly the 38 test cases defined in `TEST_INFRA.md`:

1. `test/services/screen_capture_test.dart` (TC-T1-F1-01 to TC-T1-F1-05 and TC-T2-F1-01 to TC-T2-F1-05) - 10 cases.
   Intercept MethodChannel "com.universalqaextractor.mobile/screen_capture" and EventChannel "com.universalqaextractor.mobile/frame_stream" (using TestDefaultBinaryMessengerBinding) to mock and test starting, stopping, querying status, frame callbacks, double-start prevention, double-stop safety, permission denial exceptions, stream crash resets, and resolution validations.

2. `test/services/api_service_test.dart` (TC-T1-F2-01 to TC-T1-F2-05 and TC-T2-F2-01 to TC-T2-F2-05) - 10 cases.
   Implement the ApiService contract using the interface defined in `TEST_INFRA.md` (or mock client) and verify the following HTTP POST contracts:
   - Endpoint: `POST http://<local-ip>:5000/extract`
   - Request headers: `{"Content-Type": "application/json"}`
   - Request body: `{"text": "..."}`
   - Response body (Success): `{"status": "success", "summary": "..."}`
   - Response body (Failure): `500 Server Error`
   Test successful text transmission, headers verification, body JSON formatting, response summary parsing, host IP dynamic config, server 500 error propagation, timeout handling (5s limit), unreachable host socket exceptions, short-circuiting empty payloads, and malformed JSON format exception handling.

3. `test/services/ocr_service_test.dart` (TC-T1-F3-01 to TC-T1-F3-05 and TC-T2-F3-01 to TC-T2-F3-05) - 10 cases.
   Implement the IOcrService wrapper for Google MLKit and its mock counterpart, and test: single line extraction, blank image handling, multi-line vertical sorting, noise characters filtering, cropping regions of interest (ROI), low-resolution frames, out-of-memory (OOM) handling, over-dense text limitations, unsupported image formats, and model not ready exceptions.

4. `test/pipeline_integration_test.dart` (Tiers 3 & 4) - 8 cases.
   Test integrated components:
   - TC-T3-01: End-to-End Pipeline (Frame received -> OCR -> API upload -> summary display).
   - TC-T3-02: OCR Failure blocks API request.
   - TC-T3-03: Capture stop cancels pending requests.
   - TC-T4-01: Sustained Capture Leak Test (simulates 600 cycles, verifies flat memory/disposal).
   - TC-T4-02: Active Chat Scroll Duplicate Filter (merges/deduplicates text to prevent redundant API calls).
   - TC-T4-03: Offline Queueing & Reconnection (queues data locally when API is down, flushes when connection recovers).
   - TC-T4-04: OS Lifecycle state suspension and recovery (pauses capture, serializes local queue).
   - TC-T4-05: ROI selection and cropping coordinates validation.
