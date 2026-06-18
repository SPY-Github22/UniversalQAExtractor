# Project: Universal QA Extractor Mobile

## Architecture
The mobile application is a cross-platform client built using Flutter (iOS and Android).
- **Core API Client**: Handles network communication with the local PyTorch backend.
- **Screen Capture Scaffolding**: Leverages platform channels to hook into native screen capture frameworks (ReplayKit for iOS, MediaProjection for Android).
- **OCR Service**: Wraps Google MLKit to run on-device text recognition.

```
       +---------------------------------------------------+
       |                 Flutter Application               |
       |                                                   |
       |  +--------------------+   +--------------------+  |
       |  |     OcrService     |   |     ApiService     |  |
       |  +---------+----------+   +---------+----------+  |
       |            |                        |             |
       |            | (MethodChannel)        | (HTTP POST) |
       |            v                        v             |
       |  +---------+----------+   +---------+----------+  |
       |  |  ScreenCapture API |   |  http://<ip>:5000  |  |
       |  +---------+----------+   +--------------------+  |
       |            |                                      |
       +------------|--------------------------------------+
                    | (Platform Channel)
                    v
       +------------+------------+
       | Native OS Scaffolding  |
       | - Android projection    |
       | - iOS ReplayKit         |
       +-------------------------+
```

## Code Layout
- `lib/` - Dart source code
  - `services/api_service.dart` - Sends OCR text to backend
  - `services/ocr_service.dart` - Wraps Google MLKit text recognition
  - `services/screen_capture_service.dart` - Controls screen capture channel
- `test/` - Unit tests for Dart services
  - `api_service_test.dart`
  - `ocr_service_test.dart`
- `android/` - Native Android project files
- `ios/` - Native iOS project files

## Milestones
| # | Name | Scope | Dependencies | Status | Conversation ID |
|---|------|-------|--------------|--------|-----------------|
| 1 | Test Suite & Infrastructure (E2E Track) | Design comprehensive test suite and infra | None | DONE | dcd168be-53dc-49ca-a633-a5afcfd30ce8 |
| 2 | Project Initialization & Flutter Init | Initialize Flutter app structure and configuration | None | DONE | 3606899f-371a-4b64-b6bb-e4944e789281 |
| 3 | Implement Core API Client | Write ApiService and unit tests | M2 | DONE | 3606899f-371a-4b64-b6bb-e4944e789281 |
| 4 | Implement Screen Capture Scaffolding | Write screen capture service and native platforms scaffolding | M2 | IN_PROGRESS | 3606899f-371a-4b64-b6bb-e4944e789281 |
| 5 | Implement OCR Processing Service | Write OcrService wrapper, mock integration, and unit tests | M2 | PLANNED | 3606899f-371a-4b64-b6bb-e4944e789281 |
| 6 | Integration & Final E2E Test Pass | Verification of full system against E2E test suite | M1, M3, M4, M5 | PLANNED | 3606899f-371a-4b64-b6bb-e4944e789281 |

## Interface Contracts
### ApiService ↔ Local Backend
- **Endpoint**: `POST http://<local-ip>:5000/extract`
- **Headers**: `{"Content-Type": "application/json"}`
- **Request Body**:
  ```json
  {
    "text": "Extracted chat text line 1\nExtracted chat text line 2"
  }
  ```
- **Response Body (Success)**:
  ```json
  {
    "status": "success",
    "summary": "Summarized questions..."
  }
  ```

### ScreenCaptureService Platform Channel
- **Channel Name**: `com.universalqaextractor.mobile/screen_capture`
- **Method: `startCapture`**
- Arguments: none
- Returns: `bool` (indicating success of starting the capture stream)
- **Method: `stopCapture`**
- Arguments: none
- Returns: `bool` (indicating success of stopping the capture stream)
