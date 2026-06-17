import os
import time

# FORCE ALL CACHES TO THE LOCAL D: DRIVE TO SAVE C: DRIVE SPACE
PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
CACHE_DIR = os.path.join(PROJECT_ROOT, ".cache")

os.environ["HF_HOME"] = os.path.join(CACHE_DIR, "huggingface")
os.environ["TORCH_HOME"] = os.path.join(CACHE_DIR, "torch")
os.environ["EASYOCR_MODULE_PATH"] = os.path.join(CACHE_DIR, "easyocr")

from src.capture import ScreenCapture
from src.ocr import OCREngine

def main():
    print("Starting Universal QA Extractor - Local Prototype")
    
    # Initialize engines
    capturer = ScreenCapture()
    ocr_engine = OCREngine()

    print("Entering capture loop. Press Ctrl+C to stop.")
    
    try:
        while True:
            # 1. Capture the screen (or specific region)
            # For testing, we capture a portion of the screen (top left corner)
            # You would normally drag-select the chat box area.
            capturer.set_capture_region(top=100, left=100, width=800, height=600)
            frame = capturer.capture_frame()

            # 2. Extract text locally
            text_blocks = ocr_engine.extract_text(frame)
            
            if text_blocks:
                print("\n--- Detected Text ---")
                for text in text_blocks:
                    print(text)
                print("---------------------")

            # 3. Wait before next capture (e.g., 5 seconds to prevent high CPU usage)
            time.sleep(5)

    except KeyboardInterrupt:
        print("\nStopping QA Extractor.")

if __name__ == "__main__":
    main()
