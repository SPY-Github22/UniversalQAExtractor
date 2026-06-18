# Original User Request

## Initial Request — 2026-06-18T00:23:17+05:30

# Teamwork Project Prompt — Draft

> Status: Ready for launch — awaiting user approval
> Goal: Craft prompt → get user approval → delegate to teamwork_preview

Build a cross-platform mobile application (iOS/Android) that acts as a client for a local Universal QA Extractor. The app must capture the mobile screen, perform on-device OCR to read meeting chat boxes (Zoom/Meet), and send the extracted text over the local network to a local PyTorch ML backend for question summarization.

Working directory: d:\Projects\UniversalQAExtractor\mobile
Integrity mode: development

## Requirements

### R1. Cross-Platform Mobile Client
Build a mobile application structure capable of running on both iOS and Android. The agent team may decide the framework (e.g., Flutter, React Native, or Native). It must connect to a local API endpoint (`http://<local-ip>:5000/extract`) to transmit text.

### R2. Screen Capture & OCR Architecture
The codebase must include the architectural scaffolding and core logic for native screen broadcasting (e.g., ReplayKit for iOS, MediaProjection for Android) and on-device OCR (e.g., Google MLKit). 

## Acceptance Criteria

### Verification & Core Logic
- [ ] Core API connection logic is implemented and verifiable via unit tests.
- [ ] The architectural scaffolding for screen capture and OCR is completely written and documented.
- [ ] Comprehensive unit tests are written for the core logic (API requests, text formatting, OCR parsing). No end-to-end physical device testing is required at this stage.
