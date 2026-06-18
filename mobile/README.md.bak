# Universal QA Extractor - Mobile Cross-Platform App

This directory contains the scaffolding for the mobile application version of the Universal QA Extractor.

## Architecture
Mobile platforms (iOS and Android) have strict security sandboxes that prevent background applications from reading the screen data of other apps (like a running Zoom call) silently. 

To overcome this, the Mobile application operates using **Screen Broadcasting**:
1. The user launches the Universal QA Extractor app.
2. The user initiates a "Screen Broadcast" (ReplayKit on iOS, MediaProjection on Android).
3. The app captures frames, performs on-device OCR (using MLKit), and identifies chat boxes.
4. The text is sent over the local network to the Desktop Server (`http://<YOUR_PC_IP>:5000/extract`) to run the heavy ML summarization.

## Prerequisites for Development
* Flutter SDK
* Android Studio (for Android build tools)
* Xcode (for iOS build tools)

## Directory Structure
* `lib/` - Dart source code for the Flutter app.
* `lib/services/ocr_service.dart` - Integration with Google MLKit for on-device text recognition.
* `lib/services/api_service.dart` - Handles POST requests to the local Python API.
* `android/` - Native Android project files (contains MediaProjection service).
* `ios/` - Native iOS project files (contains ReplayKit broadcast extension).

## Status
Currently, this is a placeholder directory representing Phase 7 of the implementation plan (Mobile Architecture Design). Due to the complexity of native screen capture extensions, the full Dart/Swift/Kotlin code will be implemented in subsequent development cycles.
