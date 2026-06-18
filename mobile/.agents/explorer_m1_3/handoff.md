# Handoff Report - Milestone 1: Project Initialization

## 1. Observation
- **Workspace State**:
  - Investigated the directory `d:\Projects\UniversalQAExtractor\mobile`. Only one user-facing file was found: `README.md`. No Flutter project files (such as `pubspec.yaml`, `lib/`, `android/`, `ios/`) exist yet.
  - Verified by calling `find_by_name` (Pattern: `*`) inside `d:\Projects\UniversalQAExtractor\mobile`, which returned:
    ```json
    Found 1 results: README.md
    ```
- **Architectural Scope**:
  - The project `README.md` and `.agents/orchestrator/PROJECT.md` outline the target architecture:
    - **Native OS Scaffolding**: Android MediaProjection service and iOS ReplayKit broadcast extension.
    - **OCR Service**: Wrapper around `google_mlkit_text_recognition` for on-device text extraction.
    - **API Service**: Communicates with the local Flask server on `http://<IP>:5000/extract`.
- **API Contract Discrepancy**:
  - In `d:\Projects\UniversalQAExtractor\mobile\.agents\orchestrator\PROJECT.md` (lines 58-64), the API contract is defined as:
    - Request: `{"text": "Extracted chat text..."}`
    - Response: `{"status": "success", "summary": "Summarized questions..."}`
  - In `d:\Projects\UniversalQAExtractor\server\app.py` (lines 35-55), the actual server API is implemented as:
    ```python
    35:     data = request.json
    36:     chat_text = data.get('chat', '')
    ...
    55:     return jsonify({"questions": questions_list})
    ```
    - Request expectations: JSON object containing key `"chat"` (not `"text"`).
    - Response format: JSON object containing key `"questions"`, which is a list of strings (not `"summary"` as a single string).

## 2. Logic Chain
- Since the workspace does not contain any Flutter files, we need to run a `flutter create` command.
- To target only the mobile platforms (Android and iOS) and avoid cluttering the repository with unused directories (e.g. `web`, `macos`, `windows`, `linux`), we should specify platform constraints.
- To ensure package name and bundle identifiers match the project specs, we should use the organization `--org com.universalqa.extractor` and project name `--project-name mobile`.
- Because the backend server already exists and defines a specific API contract (`chat` key in request, list of `questions` in response), the client implementation in Milestone 2 must adhere to the Flask contract in `server/app.py` rather than the draft contract in `PROJECT.md`.
- On-device text recognition requires `google_mlkit_text_recognition`. This library relies on Google ML Kit, which requires:
  - Android minimum SDK of at least 21 (and ideally 21 or 23 for optimal compatibility).
  - iOS minimum deployment target of 13.0 (configured in CocoaPods).
- For unit and integration testing without physical devices, mocking the HTTP client, OCR engine, and platform channel is required. `mocktail` is the best choice because it does not require code generation (unlike `mockito` + `build_runner`).

## 3. Caveats
- **Environment Verification**: Checking the local Flutter SDK version via `flutter --version` timed out waiting for user approval. It is assumed that a standard Flutter SDK (>= 3.0.0) is installed and available on the system PATH.
- **On-Device Testing**: On-device OCR (`google_mlkit_text_recognition`) and platform screen capture require target platforms (Android/iOS simulators or devices) to run. The E2E and unit tests must extensively mock these dependencies.

## 4. Conclusion
- The Flutter project must be initialized in `d:\Projects\UniversalQAExtractor\mobile`.
- The API Client must use the actual Flask contract: `{"chat": "string"}` -> `{"questions": ["string"]}`.
- Recommended dependencies to add:
  - `http` (HTTP communications)
  - `google_mlkit_text_recognition` (On-device OCR)
  - `mocktail` (dev_dependency for unit testing and mocking)

### Step-by-Step Implementation Strategy for the Worker:
1. **Preserve `README.md`**: Back up `d:\Projects\UniversalQAExtractor\mobile\README.md` before initializing.
2. **Run Initialization**: Execute `flutter create` with specific arguments inside `d:\Projects\UniversalQAExtractor\mobile`:
   ```powershell
   flutter create --org com.universalqa.extractor --project-name mobile --platforms android,ios .
   ```
3. **Restore `README.md`**: Merge the backed-up mobile architectural `README.md` back into the root of the mobile folder.
4. **Add Dependencies**:
   Run the following commands to add the necessary libraries (this will automatically fetch the latest compatible versions):
   ```powershell
   flutter pub add http
   ```
   ```powershell
   flutter pub add google_mlkit_text_recognition
   ```
   ```powershell
   flutter pub add --dev mocktail
   ```
5. **Configure Android Platform Settings**:
   - Locate `android/app/build.gradle`.
   - Update `minSdkVersion` to `21` (or `23` if required by Google ML Kit).
6. **Configure iOS Platform Settings**:
   - Locate `ios/Podfile`.
   - Uncomment and update the platform line to: `platform :ios, '13.0'`.
7. **Scaffold Directories**:
   Create the following folder structure and empty files inside `lib/` and `test/`:
   - `lib/services/`
     - `lib/services/api_service.dart` (API communications wrapper)
     - `lib/services/ocr_service.dart` (ML Kit OCR wrapper)
     - `lib/services/screen_capture_service.dart` (Platform channel interface)
   - `lib/views/`
     - `lib/views/home_page.dart` (Main UI screen layout)
   - `test/services/`
     - `test/services/api_service_test.dart` (API unit/mock tests)
     - `test/services/ocr_service_test.dart` (OCR service unit/mock tests)
8. **Clean Boilerplate**:
   - Remove the default `test/widget_test.dart`.
   - Replace the default counter app in `lib/main.dart` with a basic UI shell that loads `lib/views/home_page.dart`.
9. **Verify Build**:
   - Run `flutter pub get` to verify package resolution.
   - Run `flutter analyze` to ensure there are no syntax or static analysis errors in the placeholder scaffold.

## 5. Verification Method
- **Command line verification**:
  - Run `flutter analyze` inside `d:\Projects\UniversalQAExtractor\mobile`.
  - Run `flutter test` (which should run the empty placeholder tests successfully).
- **Files to inspect**:
  - `pubspec.yaml` (to confirm dependencies `http`, `google_mlkit_text_recognition`, and dev dependency `mocktail` are added).
  - `android/app/build.gradle` (to check `minSdkVersion` is at least 21).
  - `ios/Podfile` (to check `platform :ios, '13.0'` is uncommented/set).
  - Confirm the folders (`lib/services/`, `lib/views/`, `test/services/`) exist.
