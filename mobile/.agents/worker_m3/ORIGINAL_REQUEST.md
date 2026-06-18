## 2026-06-18T02:15:00Z
You are the Worker for Milestone 3 (Screen Capture Scaffolding).
Your working directory is d:\Projects\UniversalQAExtractor\mobile\.agents\worker_m3.
Your task is to fix the issues identified in `lib/services/screen_capture_service.dart` and `test/services/screen_capture_test.dart` by implementing the fix strategy recommended by the Milestone 3 Explorers.

Instructions:
1. Read the explorer recommendations and patch/proposed files in:
   - `d:\Projects\UniversalQAExtractor\mobile\.agents\explorer_m3_1\handoff.md` and patches `screen_capture_service.patch`, `screen_capture_test.patch`
   - `d:\Projects\UniversalQAExtractor\mobile\.agents\explorer_m3_3\handoff.md` and proposed files `proposed_screen_capture_service.dart`, `proposed_screen_capture_test.dart`
2. Implement the fixes to:
   - `lib/services/screen_capture_service.dart`
   - `test/services/screen_capture_test.dart`
3. Make sure to:
   - Add checks `if (!_frameController.isClosed)` in `ScreenCaptureService` before adding events or errors.
   - Implement serialization of start/stop calls using a Mutex/async-lock queue to prevent concurrent race conditions.
   - Update `checkIsCapturing()` to synchronize the frame stream subscription (start if capturing natively, cancel if not).
   - Ensure the updated tests compile and run cleanly.
4. Run `flutter test` using run_command to verify your work.
5. Write your handoff.md reporting what changes you made and the build/test outcomes.

MANDATORY INTEGRITY WARNING — DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A Forensic Auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.
