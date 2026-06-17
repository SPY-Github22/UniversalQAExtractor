# Universal QA Extractor

A 100% local, API-free tool designed to extract and summarize questions from any live video meeting chat (Zoom, Google Meet, Teams, etc.) across platforms.

## Overview
This tool operates entirely on your own hardware to protect your privacy. It works by:
1. Continuously capturing a designated region of your screen (where the chat box is located).
2. Using local Optical Character Recognition (OCR) to convert the screen pixels into text.
3. Feeding the raw text into a locally running Large Language Model (LLM) to summarize and extract the top questions asked.

No data is ever sent to the cloud. No API keys are required.

## Installation

### Prerequisites
* Python 3.10+
* A PC with a dedicated GPU is highly recommended for running the local LLM and OCR smoothly.

### Setup
1. Clone this repository.
2. Create a virtual environment: `python -m venv venv`
3. Activate the environment: `.\venv\Scripts\activate` (Windows) or `source venv/bin/activate` (Mac/Linux)
4. Install dependencies: `pip install -r requirements.txt`

## Usage
Run the main script:
```bash
python main.py
```
*Note: The first time you run this, it will download the EasyOCR models (~100MB) and the quantized Local LLM.*

## Current Phase
This project is currently in early development (Phases 1-3). The prototype captures screen data and extracts raw text using EasyOCR.
