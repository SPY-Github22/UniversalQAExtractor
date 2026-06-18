# Universal QA Extractor

A 100% local, API-free tool that extracts and summarizes key questions from any live meeting chat — across **any platform and any app**.

> 🔒 No data ever leaves your machine. No API keys. No internet required.

---

## How It Works

```
Meeting Chat (any app)
       │
       ├─ PC Browser  ──► Chrome Extension scrapes chat DOM
       ├─ PC Native   ──► Tray App captures screen + OCR
       └─ Mobile      ──► Flutter app captures screen + MLKit OCR
                │
                ▼
        POST /extract  (local network)
                │
                ▼
    Fine-tuned T5 Model (runs locally)
                │
                ▼
       List of Key Questions
```

---

## Installation

### Prerequisites
- Python 3.10+
- GPU recommended (for OCR and model inference speed)

### Setup
```bash
git clone https://github.com/SPY-Github22/UniversalQAExtractor
cd UniversalQAExtractor
python -m venv venv
.\venv\Scripts\activate         # Windows
pip install -r requirements.txt
```

### Train the Model (one time only)
```bash
python ml/train.py
```

---

## Usage

### Step 1 — Start the Backend
```bash
python server/app.py
```
Runs on `http://localhost:5000`. Must be running for all clients to work.

---

### Step 2A — PC (Browser apps: Google Meet, Zoom Web, Teams Web)
Load `extension/` as an unpacked Chrome extension:
1. Open `chrome://extensions`
2. Enable **Developer Mode**
3. Click **Load unpacked** → select the `extension/` folder
4. Join a browser meeting → click the extension popup → **Get Top Questions**

---

### Step 2B — PC (Native apps: Zoom, Teams, Slack, Discord — ANY app)
```bash
python tray_app.py
```
- A **blue dot** appears in your system tray
- During any meeting, press **`Ctrl+Shift+Q`**
- The screen is captured, OCR'd, and questions appear in a popup
- Or right-click the tray icon → **Capture Now**

---

### Step 2C — Mobile (Android)
Build and run the Flutter app in `mobile/`:
```bash
cd mobile
flutter pub get
flutter run
```
- Enter your PC's local IP address in the app
- Tap **Start Capture** → the app reads your screen and sends text to the backend

---

## Project Structure

```
UniversalQAExtractor/
├── server/         # Flask API + T5 model inference
├── ml/             # Training pipeline (synthetic data + T5 fine-tuning)
├── src/            # Screen capture (mss) + OCR (EasyOCR) modules
├── extension/      # Chrome extension (Manifest V3)
├── tray_app.py     # PC tray app for native desktop apps
└── mobile/         # Flutter cross-platform mobile client
```

---

## Notes
- First run of OCR will download EasyOCR models (~100MB)
- The T5 model is saved in `.cache/custom_model/` after training
- Mobile and tray app connect to the backend over your **local network** (same Wi-Fi)
