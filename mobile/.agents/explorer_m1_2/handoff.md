# Handoff Report - Milestone 1: Project Initialization Exploration

## 1. Observation
* **Workspace Directory Contents**:
  The directory `d:\Projects\UniversalQAExtractor\mobile` contains:
  * `.agents/` (directory)
  * `README.md` (1627 bytes)
* **README.md Content Analysis**:
  The existing `README.md` details the architecture of the mobile app (Screen Broadcasting using ReplayKit on iOS and MediaProjection on Android, local OCR using MLKit, sending text to local desktop API at `http://<YOUR_PC_IP>:5000/extract`).
  * Specifically, lines 20-25 describe the expected file structure:
    ```
    * `lib/` - Dart source code for the Flutter app.
    * `lib/services/ocr_service.dart` - Integration with Google MLKit for on-device text recognition.
    * `lib/services/api_service.dart` - Handles POST requests to the local Python API.
    * `android/` - Native Android project files (contains MediaProjection service).
    * `ios/` - Native iOS project files (contains ReplayKit broadcast extension).
    ```
  * Lines 26-27 indicate the project is currently a placeholder representing Phase 7 of the implementation plan:
    ```
    Currently, this is a placeholder directory representing Phase 7 of the implementation plan (Mobile Architecture Design).
    ```
* **Command Line Limitations**:
  Running terminal commands (such as `flutter --version`) in this environment timed out due to the lack of interactive approval capabilities. Therefore, the initialization must be designed for execution by the next agent (implementer) who will have command authorization.

---

## 2. Logic Chain
1. **Empty Structure**: Since the directory currently contains only `README.md` and the `.agents` folder, a complete Flutter project structure needs to be generated.
2. **Platform Constraints**: The project architecture specifically targets iOS and Android. Restricting the platform creation to `android` and `ios` will prevent polluting the workspace with unnecessary folders (windows, macos, linux, web).
3. **Command Selection**: The Flutter command to create a project in the current directory with the specific organization prefix (`com.universalqa.extractor`), custom project name (`universal_qa_extractor`), and platform limits is:
   ```bash
   flutter create --org com.universalqa.extractor --project-name universal_qa_extractor --platforms android,ios .
   ```
4. **Preservation of Documentation**: Since `flutter create` generates a default `README.md`, running it directly in the `mobile` folder will overwrite the existing architectural documentation in `d:\Projects\UniversalQAExtractor\mobile\README.md`. Therefore, `README.md` must be backed up before running the command and restored afterward.
5. **Dependencies**:
   * **Networking**: The app must communicate with the Desktop Server using POST requests. We select the standard `http` library.
   * **OCR**: The app requires on-device OCR. We select `google_mlkit_text_recognition` because it runs entirely locally, aligning with the "local-only, privacy-focused" philosophy.
   * **Permissions**: Access to camera, notifications, or screen capture requires runtime permissions, calling for the `permission_handler` package.
   * **State Management**: For robust state management (managing capture state, API configurations, and OCR status), we recommend `flutter_riverpod` (v2+).
6. **Native Configurations**:
   * **Android**: To support media projection in the background, a Foreground Service must be configured in `AndroidManifest.xml` with `FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_MEDIA_PROJECTION` permissions. Also, cleartext HTTP traffic must be enabled to communicate with the local PC IP address. The minSdk must be set to `21` in `android/app/build.gradle` to support Google ML Kit.
   * **iOS**: Must be configured with local network permission (`NSLocalNetworkUsageDescription`) and HTTP transport security rules (`NSAllowsArbitraryLoads`) to allow communication with the local server.

---

## 3. Caveats
* **Environment Capability**: It is assumed that the worker running the command has Flutter SDK and Android/iOS build tools correctly configured and available on their system PATH.
* **iOS Native Setup**: While the basic iOS folders and `Info.plist` changes can be configured, creating a Broadcast Upload Extension for ReplayKit requires Xcode on macOS and an Apple Developer Profile to configure App Groups. This part of the setup cannot be fully completed on a Windows development machine alone.
* **Android MediaProjection Service**: Milestone 1 only configures the project structure and manifest declarations. The actual Kotlin service for background screen capture will be implemented in subsequent milestones.

---

## 4. Conclusion and Step-by-Step Implementation Strategy

### Recommended Pubspec Configuration (`pubspec.yaml`)
```yaml
name: universal_qa_extractor
description: "Mobile cross-platform client for Universal QA Extractor using on-device OCR and local network API integration."
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.6
  http: ^1.2.0
  google_mlkit_text_recognition: ^0.13.0
  permission_handler: ^11.3.0
  flutter_riverpod: ^2.5.1

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0
```

### Proposed Folder Structure to Initialize
Within `lib/`, set up the following directories and placeholder files:
* `lib/models/qa_frame.dart`
* `lib/services/ocr_service.dart`
* `lib/services/api_service.dart`
* `lib/providers/capture_provider.dart`
* `lib/screens/home_screen.dart`
* `lib/utils/constants.dart`

---

### Step-by-Step Implementation Plan for the Worker

#### Step 1: Back up the README.md File
Move/copy `d:\Projects\UniversalQAExtractor\mobile\README.md` to a temporary location or file (e.g., `README.md.bak`) to prevent `flutter create` from overwriting it.

#### Step 2: Initialize the Flutter Project
Execute the initialization command in `d:\Projects\UniversalQAExtractor\mobile`:
```powershell
flutter create --org com.universalqa.extractor --project-name universal_qa_extractor --platforms android,ios --overwrite .
```

#### Step 3: Restore the README.md File
Delete the generated `README.md` and rename `README.md.bak` back to `README.md` to preserve the original architectural documentation.

#### Step 4: Configure pubspec.yaml Dependencies
Replace/update the dependencies and dev_dependencies in the generated `pubspec.yaml` with the recommended packages (`http`, `google_mlkit_text_recognition`, `permission_handler`, `flutter_riverpod`).

#### Step 5: Resolve Flutter Dependencies
Run the command:
```powershell
flutter pub get
```

#### Step 6: Create Folder Structure and Placeholders
Create the subfolders and stub files under `lib/`:
* Create `lib/models/`, `lib/services/`, `lib/providers/`, `lib/screens/`, `lib/utils/`.
* Write a skeleton implementation for `lib/services/ocr_service.dart`:
  ```dart
  class OCRService {
    // Stub for Google ML Kit Text Recognition integration
    Future<String> recognizeTextFromImage(String imagePath) async {
      return "Recognized text stub";
    }
  }
  ```
* Write a skeleton implementation for `lib/services/api_service.dart`:
  ```dart
  import 'package:http/http.dart' as http;

  class APIService {
    Future<bool> sendExtractedText(String serverIp, String text) async {
      // Stub for sending POST requests to serverIp:5000/extract
      return true;
    }
  }
  ```
* Create a simple Home Screen in `lib/screens/home_screen.dart` providing a UI stub to display the server status, input for server IP, and buttons to start/stop screen broadcasting.

#### Step 7: Android Configuration Updates
1. Open `android/app/build.gradle` and update `minSdkVersion` to `21`.
2. Open `android/app/src/main/AndroidManifest.xml` and make the following additions:
   * **Permissions** (above `<application>`):
     ```xml
     <uses-permission android:name="android.permission.INTERNET"/>
     <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
     <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION"/>
     ```
   * **Cleartext traffic support** (inside `<application>` tag):
     ```xml
     android:usesCleartextTraffic="true"
     ```
   * **Foreground Service registration** (inside `<application>` tag):
     ```xml
     <service
         android:name=".MediaProjectionService"
         android:foregroundServiceType="mediaProjection"
         android:exported="false">
     </service>
     ```

#### Step 8: iOS Configuration Updates
Open `ios/Runner/Info.plist` and add the following keys to allow local network requests:
```xml
<key>NSLocalNetworkUsageDescription</key>
<string>This app requires access to the local network to send text frames to the desktop API server.</string>
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

#### Step 9: Verify Project Integrity
Execute:
```powershell
flutter analyze
```
Confirm that the analyzer reports no errors or warnings.

---

## 5. Verification Method
1. **Directory Structure Check**: Verify the existence of the following directories:
   * `android/`
   * `ios/`
   * `lib/services/`
   * `lib/screens/`
   * `lib/models/`
   * `lib/providers/`
   * `lib/utils/`
2. **Documentation Check**: Verify that `README.md` contains the architectural details starting with `# Universal QA Extractor - Mobile Cross-Platform App` (and is not the default Flutter readme).
3. **pubspec.yaml Check**: Inspect `pubspec.yaml` to ensure the name is `universal_qa_extractor` and dependencies (`http`, `google_mlkit_text_recognition`, `permission_handler`, `flutter_riverpod`) are present.
4. **Build Tool Check**: Run `flutter pub get` and `flutter analyze` from the command line. They must execute successfully and return a zero exit code (no errors).
