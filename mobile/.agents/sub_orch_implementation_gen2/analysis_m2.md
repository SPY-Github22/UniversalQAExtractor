# Milestone 2 Synthesis Analysis Report

## Consensus
There is a critical API contract mismatch between the mobile client implementation and the live Flask backend (`server/app.py`).

1. **Response Schema Mismatch**:
   - The current `ApiService` expects a JSON response of the form: `{"status": "success", "summary": "..."}` and returns a single `String`.
   - The Flask backend actually returns: `{"questions": ["Question 1", "Question 2", ...]}`.
   - At runtime, the client will fail to parse this (throwing `Failed status: null` because `status` is missing).

2. **Interface Discrepancy**:
   - `TEST_INFRA.md` defines the client interface to return `Future<List<String>>` and states that the parser parses a list of questions.
   - The actual implementation of `IApiService` returns `Future<String>`.

3. **Green Test Fallacy**:
   - Existing unit and integration tests mock HTTP responses using the incorrect `status`/`summary` schema. Consequently, they pass green despite the runtime incompatibility with the real backend.

## Resolved Conflicts
- **Explorer 2** suggested the implementation was correct due to internal consistency (both `ApiService` and the mock tests aligned on the `summary` string).
- **Explorers 1 & 3** correctly pointed out the external incompatibility with the actual Flask server (`server/app.py`).
- **Resolution**: We adopt the findings of Explorers 1 and 3. The client must be modified to return `Future<List<String>>` and parse the backend's `questions` key to ensure E2E integration works against the live server.

## Required Modifications
1. **`lib/services/api_service.dart`**:
   - Change `IApiService.extractQuestions` signature to return `Future<List<String>>`.
   - Modify `ApiService` implementation to:
     - Return `[]` if the input text is empty or whitespace (short-circuit).
     - Parse the backend response body's `questions` key.
     - Accept an optional dynamic `deviceId` in its constructor (defaulting to `'mock-device-id'`).
2. **`test/services/api_service_test.dart`**:
   - Update all mock client responses to return `{"questions": [...]}`.
   - Assert that `extractQuestions` returns a `List<String>`.
3. **`test/pipeline_integration_test.dart`**:
   - Update mock HTTP responses to match the `{"questions": [...]}` contract.
