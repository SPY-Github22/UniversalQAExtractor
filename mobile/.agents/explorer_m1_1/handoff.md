# Handoff Report — explorer_m1_1

## Observation
* **Workspace Analysis**:
  * The workspace directory `d:\Projects\UniversalQAExtractor\mobile` contains:
    * `README.md` (project overview and requirements)
    * `.agents` (agent directories)
  * No existing Flutter project code, `pubspec.yaml`, or standard Flutter directories (`lib`, `android`, `ios`) exist yet.
* **Server Analysis**:
  * The server is implemented in `d:\Projects\UniversalQAExtractor\server\app.py`.
  * It exposes a POST endpoint `/extract` on port 5000.
  * Request payload format: `{"chat": "<raw_text_to_extract>"}`.
  * Response format: `{"questions": ["question 1", "question 2", ...]}`, or `{"error": "..."}` on failure.
* **Command Execution Limit**:
  * Attempting to run `flutter --version` via the terminal timed out waiting for user approval. Commands must be assumed to be run by the implementer manually or programmatically with appropriate permissions.

## Logic Chain
* **Project Initialization**:
  * Since `README.md` is present in the target directory `d:\Projects\UniversalQAExtractor\mobile`, running `flutter create` directly could overwrite it. Therefore, it must be backed up first and restored/merged later.
  * The project name should be a valid Dart package name (`universal_qa_extractor`).
  * The organization name should be `com.universalqa.extractor` to generate standard package/bundle IDs (e.g. `com.universalqa.extractor.universal_qa_extractor`).
  * The app targets Android (MediaProjection) and iOS (ReplayKit), so specifying `--platforms android,ios` is recommended to avoid cluttering the repository with unused web/desktop directories.
* **Dependency Analysis**:
  * **Networking**: The app must send extracted text to `http://<YOUR_PC_IP>:5000/extract`. This requires the `http` package for HTTP POST requests.
  * **On-Device OCR**: Capturing frames and doing local text recognition requires `google_mlkit_text_recognition`.
  * **Device Permissions**: Handling permissions for screen capture and storage requires `permission_handler`.
  * **Settings Storage**: The app needs to save the user-configured server IP and port, which requires `shared_preferences`.
  * **State Management**: Using `provider` is a lightweight, standard approach to manage the state of connection, OCR results, and active broadcasting.
* **Folder Structure**:
  * A clean, modular folder structure is needed inside `lib/` to organize the source code, separating UI, services, models, and providers.

## Caveats
* **Flutter SDK Availability**: It is assumed that Flutter SDK is installed and available in the environment's PATH.
* **Native Screen Capture**: Background screen broadcasting (using `MediaProjection` on Android and `ReplayKit` on iOS) requires native platform-specific implementations (Kotlin and Swift). Flutter create will only set up the basic runners; custom native services and broadcast upload extensions must be created in later milestones.
* **iOS Memory Limitations**: ReplayKit Broadcast Upload Extensions have a strict memory limit of 50MB. Initializing a Flutter engine inside the extension will likely cause OOM crashes. The recommended approach is to run OCR directly in the native iOS extension and send the text back via shared databases (App Groups) or keep the core logic simple.

## Conclusion
The project is ready to be initialized. The worker should perform the following step-by-step implementation strategy.

### Step-by-Step Implementation Strategy

1. **Backup Existing README**:
   * Rename `d:\Projects\UniversalQAExtractor\mobile\README.md` to `README.md.bak`.

2. **Initialize Flutter Project**:
   * Navigate to `d:\Projects\UniversalQAExtractor\mobile` and run:
     ```bash
     flutter create --org com.universalqa.extractor --project-name universal_qa_extractor --platforms android,ios .
     ```

3. **Restore README**:
   * Restore the backup `README.md.bak` to `README.md`.

4. **Update `pubspec.yaml`**:
   * Add the following dependencies under `dependencies`:
     ```yaml
     http: ^1.2.0
     google_mlkit_text_recognition: ^0.13.0
     permission_handler: ^11.3.0
     shared_preferences: ^2.2.0
     provider: ^6.1.2
     ```
   * Run `flutter pub get` to download the packages.

5. **Create Folder Structure**:
   * Create the following directories inside `lib/`:
     * `lib/models`
     * `lib/services`
     * `lib/providers`
     * `lib/views`
     * `lib/views/widgets`

6. **Create Skeleton Service Files**:
   * **`lib/services/api_service.dart`**: Skeleton with basic POST network request method targeting the `/extract` endpoint.
   * **`lib/services/ocr_service.dart`**: Skeleton wrapping `google_mlkit_text_recognition`.
   * **`lib/services/broadcast_service.dart`**: Skeleton defining platform channels (MethodChannel/EventChannel) to interface with native MediaProjection/ReplayKit.

7. **Configure Minimum SDK and Platform Targets**:
   * **Android** (`android/app/build.gradle`): Set `minSdkVersion` to `21` (required by ML Kit and MediaProjection).
   * **iOS** (`ios/Podfile`): Set the deployment target platform to `12.0` or higher.

## Verification Method
1. Check that `pubspec.yaml` exists and contains the specified dependencies.
2. Confirm the presence of directories `lib/models`, `lib/services`, `lib/providers`, `lib/views`, `lib/views/widgets`.
3. Verify that the command `flutter pub get` executes successfully.
4. Verify that running `flutter analyze` in the `mobile/` directory completes with no errors.
