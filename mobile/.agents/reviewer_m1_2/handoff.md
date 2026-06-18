# Handoff Report: Milestone 1 - Project Initialization Review & Critic Report

## 1. Observation

### File & Directory Structure Findings
I statically analyzed the project files at `d:\Projects\UniversalQAExtractor\mobile` and observed the following directory structure:
- `pubspec.yaml`
- `lib/` containing:
  - `main.dart`
  - `screens/home_screen.dart`
  - `services/ocr_service.dart`
  - `services/api_service.dart`
  - `models/`, `providers/`, `utils/` (empty directories)
- `android/` containing *only*:
  - `app/build.gradle`
  - `app/src/main/AndroidManifest.xml`
- `ios/` containing *only*:
  - `Runner/Info.plist`
- `TEST_INFRA.md` (detailing testing abstractions and test cases)
- `README.md` and `README.md.bak`

### Key File Contents Observed

#### A. `android/app/src/main/AndroidManifest.xml`
The manifest defines permissions and services:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION"/>
...
<service
    android:name=".MediaProjectionService"
    android:foregroundServiceType="mediaProjection"
    android:exported="false">
</service>
```
However, a search of the `android` directory reveals **no Kotlin or Java source files** at all (neither `MainActivity.kt`/`MainActivity.java` nor `MediaProjectionService.kt`/`MediaProjectionService.java`).

#### B. `android/app/build.gradle`
This specifies target/min SDKs and the package namespace:
```groovy
namespace "com.universalqa.extractor.universal_qa_extractor"
compileSdkVersion 34
...
defaultConfig {
    applicationId "com.universalqa.extractor.universal_qa_extractor"
    minSdkVersion 21
    targetSdkVersion 34
    ...
}
```
However, the parent `android/` folder is missing:
- `android/build.gradle` (the project-level build script)
- `android/settings.gradle` (the multi-project settings file)
- `android/gradle.properties` (gradle configuration options)
- `android/gradlew` & `android/gradlew.bat` (gradle wrappers)
- `android/gradle/wrapper/gradle-wrapper.properties` and wrapper jars

#### C. `ios/Runner/Info.plist`
This defines network permissions:
```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Local network access required to send extracted text to local server.</string>
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```
However, the parent `ios/` folder is missing:
- `ios/Runner.xcodeproj` (Xcode project folder)
- `ios/Runner.xcworkspace` (Xcode workspace folder)
- `ios/Podfile` (CocoaPods dependency management)
- `ios/Runner/AppDelegate.swift` (App lifecycle delegate)
- Other boilerplate resources required to compile an iOS project.

#### D. `lib/services/ocr_service.dart`
```dart
class OCRService {
  Future<String> recognizeTextFromImage(String imagePath) async {
    return "Recognized text stub";
  }
}
```
This accepts `String imagePath` and returns a hardcoded string. However, `TEST_INFRA.md` lines 124–128 specify a different interface:
```dart
abstract class IOcrService {
  Future<String> recognizeText(Uint8List imageBytes);
}
```

#### E. `lib/services/api_service.dart`
```dart
class APIService {
  Future<bool> sendExtractedText(String serverIp, String text) async {
    return true;
  }
}
```
This accepts `String serverIp, String text` and returns `bool`. However:
- `PROJECT.md` lines 55–70 outline a `POST http://<local-ip>:5000/extract` endpoint using payload key `"text"` and returning `{"status": "success", "summary": "..."}`.
- `TEST_INFRA.md` lines 80–105 outline `IApiClient` with `Future<List<String>> extractQuestions(String chatText)` utilizing payload key `"chat"` and returning `{"questions": [...]}`.

### Executed Command Logs
 Proposing any `run_command` (e.g. `flutter --version`, `flutter pub get`) leads to a permission prompt timeout in the execution environment:
> `Encountered error in step execution: Permission prompt for action 'command' on target ... timed out waiting for user response.`

---

## 2. Logic Chain

1. **Incomplete Scaffolding & Build Failure**: An Android project cannot compile without top-level build scripts (`android/build.gradle` and `android/settings.gradle`) and Gradle wrappers. Similarly, an iOS project cannot compile without the `.xcodeproj` or `.xcworkspace` folder. Because these configuration files are missing, the project currently represents a disconnected subset of files rather than a buildable Flutter application.
2. **Missing Native Entry Points**: The Android manifest refers to `.MainActivity` and `.MediaProjectionService`. Since the native source files (Kotlin/Java classes) are absent from the `android/` directory, any attempt to launch or build the app would fail with `ClassNotFoundException` errors.
3. **API Contract Discrepancy**: The service code implemented in `api_service.dart` uses a signature `sendExtractedText(serverIp, text)` returning `bool`. This conflicts with the JSON structure in `PROJECT.md` (which returns a text summary) and `TEST_INFRA.md` (which returns a `List<String>` of questions via key `"chat"`). Inconsistencies across documentation, testing frameworks, and implementations will introduce integration bugs during the next milestone.
4. **OCR Service Architectural Defect**: The OCR service takes a `String imagePath`. However, real-time screen capture streams frame buffers directly in-memory (`Uint8List`). Writing frames to disk to pass them as file paths will result in massive I/O overhead and performance bottlenecks.
5. **No Dependency Injection**: The implemented `APIService` lacks an injected `http.Client`. This directly violates the mock-based device-free testing strategy documented in `TEST_INFRA.md`, making it impossible to write unit tests for networking without spawning a real server.

---

## 3. Caveats

- **No Runtime Verification**: Due to environment restrictions where `run_command` triggers non-interactive timeouts, no commands could be executed (e.g. `flutter pub get`, `flutter analyze`, or `flutter test`). All reviews are based on static analysis.
- **Milestone Scope Interpretation**: If this milestone was intended only to write placeholder text configuration files rather than initialize a compilable Flutter boilerplate, the missing files might be added in a later step. However, standard Flutter project layout conventions expect a complete scaffolding to exist at the end of initialization.

---

## 4. Conclusion

### Review Summary

**Verdict**: REQUEST_CHANGES

### Findings

#### [Critical] Finding 1: Incomplete Android & iOS Project Configurations
- **What**: Missing project-level configuration files (Gradle wrapper, top-level `build.gradle`, `settings.gradle` for Android; `.xcodeproj`, `.xcworkspace`, and `Podfile` for iOS).
- **Where**: `android/` and `ios/` root directories.
- **Why**: The app cannot be built, compiled, or opened in IDEs (Android Studio / Xcode) because the essential build infrastructure files are missing.
- **Suggestion**: Generate the standard boilerplate configurations (either by running `flutter create .` inside a local workspace where command execution is permitted, or by manually copying the missing build wrappers, settings, and project files).

#### [Critical] Finding 2: Missing Native Source Classes
- **What**: The classes `.MainActivity` and `.MediaProjectionService` declared in `AndroidManifest.xml` do not exist in the codebase.
- **Where**: `android/app/src/main/AndroidManifest.xml` (lines 14, 32)
- **Why**: Attempting to launch the app or launch the foreground capture service will cause `ClassNotFoundException` crashes.
- **Suggestion**: Create placeholder native files under `android/app/src/main/kotlin/com/universalqa/extractor/universal_qa_extractor/` for both `MainActivity.kt` and `MediaProjectionService.kt`.

#### [Major] Finding 3: API Contract & Signature Mismatches
- **What**: Discrepancies between `PROJECT.md` contracts, `TEST_INFRA.md` mock code, and the actual `APIService` signature.
- **Where**: `lib/services/api_service.dart`, `PROJECT.md` (lines 55-80), `TEST_INFRA.md` (lines 80-105).
- **Why**: `PROJECT.md` expects key `"text"` and returns a summary. `TEST_INFRA.md` expects key `"chat"` and returns a question list. `APIService` returns a boolean.
- **Suggestion**: Align the contracts. Standardize the data exchange formats (e.g., standardizing on sending the captured chat text and returning a list of extracted questions).

#### [Major] Finding 4: Lack of HTTP Dependency Injection
- **What**: The HTTP client is not injected into `APIService`.
- **Where**: `lib/services/api_service.dart`.
- **Why**: Prevents injecting `MockClient` during unit testing, breaking the device-free E2E testing framework.
- **Suggestion**: Modify `APIService` to accept an optional/required `http.Client` parameter in its constructor.

#### [Major] Finding 5: OCR Service Path Parameter Bottleneck
- **What**: `OCRService.recognizeTextFromImage` takes a `String imagePath`.
- **Where**: `lib/services/ocr_service.dart`.
- **Why**: Real-time screen capture streams frame bytes (`Uint8List`). Writing frames to disk to read them back as file paths introduces severe I/O latency.
- **Suggestion**: Define an abstract `IOcrService` (as planned in `TEST_INFRA.md`) and modify the signature to accept image bytes (`Uint8List` or a dedicated wrapper) rather than file paths.

---

### Challenge Summary

**Overall risk assessment**: HIGH

### Challenges

#### [High] Challenge 1: iOS ReplayKit Broadcast Extension Memory Limits
- **Assumption challenged**: That the iOS ReplayKit extension can load and execute heavy libraries directly.
- **Attack scenario**: iOS Broadcast Upload Extensions have a strict **50 MB memory limit**. Loading Google MLKit inside the extension process will exceed this limit, causing the extension to be terminated immediately by iOS (`EXC_RESOURCE`).
- **Blast Radius**: Screen capture crashes instantly on iOS.
- **Mitigation**: Use App Groups to send raw frame bytes from the Broadcast Extension to the main container app (which has a much higher memory limit) and run MLKit OCR in the main app process.

#### [Medium] Challenge 2: Network Reachability & Firewall Blockages
- **Assumption challenged**: The mobile device will always be able to reach the local backend server via the target IP.
- **Attack scenario**: The desktop is on a corporate network with isolated subnets, or the host firewall blocks incoming requests on port 5000.
- **Blast Radius**: The mobile app fails to transmit OCR data, rendering it inoperative.
- **Mitigation**: Implement Network Service Discovery (mDNS / NSD) to auto-detect the backend and provide connection troubleshooters in the settings UI.

#### [Medium] Challenge 3: Android 14 Media Projection Foreground Service Restrictions
- **Assumption challenged**: Continuous screen capture runs in the background indefinitely without OS intervention.
- **Attack scenario**: Android 14 (API 34) enforces strict foreground service launch conditions. Starting the projection without showing a persistent notification or before the foreground service is active will cause a `SecurityException`.
- **Blast Radius**: Media Projection fails to launch or is killed silently by the OS.
- **Mitigation**: Ensure the native Kotlin service strictly follows the API 34 startup lifecycle: request the media projection permission first, launch the foreground service with a persistent user notification, and then initiate capture inside the service context.

---

## 5. Verification Method

To independently verify the initialized configuration:
1. Try building the app targeting a device/emulator:
   - For Android: Run `flutter build apk` (or `gradlew assembleDebug` inside the `android` folder). It will fail due to the missing top-level gradle wrapper and build files.
   - For iOS: Run `flutter build ios` (or open the `ios` directory in Xcode). It will fail due to the lack of `.xcodeproj` or `.xcworkspace`.
2. Inspect the file directory tree of `android` and `ios` to confirm the absence of standard native files.
3. Compare the method signatures in `lib/services/api_service.dart` and `lib/services/ocr_service.dart` against the contracts in `PROJECT.md` and mock examples in `TEST_INFRA.md`.
