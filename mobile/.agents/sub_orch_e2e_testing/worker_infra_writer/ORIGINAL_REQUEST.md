## 2026-06-18T00:28:04+05:30

You are a Worker subagent for the E2E Testing Track.
Task: Synthesize the design recommendations from the 3 Explorer reports (located in `d:\Projects\UniversalQAExtractor\mobile\.agents\sub_orch_e2e_testing\explorer_1_report.md`, `explorer_2_report.md`, and `explorer_3_report.md`) and create `TEST_INFRA.md` at the project root (`d:\Projects\UniversalQAExtractor\mobile\TEST_INFRA.md`).

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A Forensic Auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Specifically, write `TEST_INFRA.md` to follow this structure:
# E2E Test Infra: Universal QA Extractor Mobile

## Test Philosophy
- Opaque-box, requirement-driven. No dependency on implementation design.
- Methodology: Category-Partition + BVA + Pairwise + Workload Testing.

## Feature Inventory
| # | Feature | Source (requirement) | Tier 1 | Tier 2 | Tier 3 |
|---|---------|---------------------|:------:|:------:|:------:|
| 1 | F1: Screen capture platform channel | ORIGINAL_REQUEST §R2 | 5 | 5 | ✓ |
| 2 | F2: Local API transmission | ORIGINAL_REQUEST §R1 | 5 | 5 | ✓ |
| 3 | F3: On-device OCR processing | ORIGINAL_REQUEST §R2 | 5 | 5 | ✓ |

## Test Architecture
- Explain the device-free test strategy on standard development machines (`flutter test`).
- Detail the exact mock approach for:
  - Screen Capture: Platform channel method interception via MockMethodCallHandler andEventChannel simulation.
  - API Transmission: Injected custom HTTP MockClient.
  - OCR Processing: Abstract `IOcrService` wrapper for Google MLKit with a `MockOcrService` injection.
- Specify Directory layout of tests:
  - `test/services/screen_capture_test.dart`
  - `test/services/api_service_test.dart`
  - `test/services/ocr_service_test.dart`
  - `test/pipeline_integration_test.dart`

## Real-World Application Scenarios (Tier 4)
Detail the 5 Tier 4 scenarios:
1. Sustained Capture Leak Test (continuous streaming)
2. Active Chat Scroll Duplicate Filter (overlapping text blocks)
3. Offline Queueing and Reconnection Recovery (Wi-Fi toggle)
4. OS Suspension, Termination, and Re-initialization (app state cycle)
5. Region of Interest (ROI) Cropping (bounding box selection)

## Coverage Thresholds
- Tier 1: 15 cases (5 per feature)
- Tier 2: 15 cases (5 per feature)
- Tier 3: 3 cases (cross-feature interactions)
- Tier 4: 5 realistic application scenarios
- Total: 38 test cases

## Complete Test Case Catalog
List the full 38 test cases (combining the best descriptions from the explorer reports) in structured tables with Test ID, Test Name, Input/State, Action, and Expected Output.

Write the file to `d:\Projects\UniversalQAExtractor\mobile\TEST_INFRA.md`. After writing, verify that the file exists and is complete. Then message the E2E Testing Orchestrator (conversation ID: dcd168be-53dc-49ca-a633-a5afcfd30ce8) with the path and confirmation.
