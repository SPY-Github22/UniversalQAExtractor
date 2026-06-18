"""
tray_app.py — Universal QA Extractor: PC Tray App
===================================================
Sits in the system tray. Press Ctrl+Shift+Q at any time
during a meeting (in ANY app — Zoom, Teams, Slack, Discord, etc.)
to capture the screen, OCR the chat, and display extracted questions.

Requirements: pip install pystray keyboard pillow
Backend must be running: python server/app.py
"""

import sys
import os
import threading
import tkinter as tk
from tkinter import ttk
import requests
import keyboard
import pystray
from PIL import Image, ImageDraw

# ── Path setup so src/ modules are importable ──────────────────────────────
PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, PROJECT_ROOT)

from src.capture import ScreenCapture
from src.ocr import OCREngine

# ── Config ──────────────────────────────────────────────────────────────────
SERVER_URL = "http://localhost:5000/extract"
HOTKEY     = "ctrl+shift+q"          # Change this if you prefer another combo

# ── Lazy-load the OCR engine (heavy, first use downloads models) ─────────────
_ocr_engine = None
_ocr_lock   = threading.Lock()

def get_ocr_engine():
    global _ocr_engine
    with _ocr_lock:
        if _ocr_engine is None:
            print("[OCR] Initialising EasyOCR (first run may download models)...")
            _ocr_engine = OCREngine(languages=["en"])
            print("[OCR] Ready.")
    return _ocr_engine


# ── Popup Window ─────────────────────────────────────────────────────────────
class ResultPopup:
    """Small always-on-top window that shows the extracted questions."""

    def __init__(self, questions: list[str]):
        self.root = tk.Tk()
        self.root.title("🎯 QA Extractor — Top Questions")
        self.root.configure(bg="#1e1e2e")
        self.root.attributes("-topmost", True)          # Always on top
        self.root.resizable(True, True)
        self.root.geometry("520x400")

        # ── Header ──
        header = tk.Label(
            self.root,
            text="📋  Top Questions from Meeting",
            font=("Segoe UI", 13, "bold"),
            bg="#1e1e2e",
            fg="#cdd6f4",
            pady=12,
        )
        header.pack(fill="x")

        # ── Separator ──
        sep = ttk.Separator(self.root, orient="horizontal")
        sep.pack(fill="x", padx=16)

        # ── Scrollable question list ──
        frame = tk.Frame(self.root, bg="#1e1e2e")
        frame.pack(fill="both", expand=True, padx=16, pady=10)

        canvas   = tk.Canvas(frame, bg="#1e1e2e", highlightthickness=0)
        scrollbar = ttk.Scrollbar(frame, orient="vertical", command=canvas.yview)
        inner    = tk.Frame(canvas, bg="#1e1e2e")

        inner.bind(
            "<Configure>",
            lambda e: canvas.configure(scrollregion=canvas.bbox("all"))
        )
        canvas.create_window((0, 0), window=inner, anchor="nw")
        canvas.configure(yscrollcommand=scrollbar.set)

        canvas.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")

        # Render each question as a card
        if not questions:
            tk.Label(
                inner,
                text="No questions found.\nTry capturing a chat area with more text.",
                font=("Segoe UI", 11),
                bg="#1e1e2e",
                fg="#a6adc8",
                justify="left",
                wraplength=460,
                pady=8,
            ).pack(anchor="w", pady=4)
        else:
            for i, q in enumerate(questions, 1):
                card = tk.Frame(inner, bg="#313244", bd=0)
                card.pack(fill="x", pady=4, padx=2)

                num_lbl = tk.Label(
                    card,
                    text=f" {i}.",
                    font=("Segoe UI", 11, "bold"),
                    bg="#313244",
                    fg="#89b4fa",
                    width=3,
                    anchor="nw",
                )
                num_lbl.pack(side="left", padx=(6, 0), pady=8)

                q_lbl = tk.Label(
                    card,
                    text=q,
                    font=("Segoe UI", 11),
                    bg="#313244",
                    fg="#cdd6f4",
                    justify="left",
                    wraplength=440,
                    anchor="nw",
                )
                q_lbl.pack(side="left", padx=6, pady=8, fill="x", expand=True)

        # ── Close button ──
        close_btn = tk.Button(
            self.root,
            text="✕  Close",
            command=self.root.destroy,
            bg="#f38ba8",
            fg="#1e1e2e",
            font=("Segoe UI", 10, "bold"),
            relief="flat",
            padx=14,
            pady=6,
            cursor="hand2",
        )
        close_btn.pack(pady=(0, 12))

        # Mouse-wheel scrolling support
        self.root.bind_all("<MouseWheel>", lambda e: canvas.yview_scroll(
            int(-1 * (e.delta / 120)), "units"
        ))

        self.root.mainloop()


# ── Core extraction pipeline ──────────────────────────────────────────────────
def run_extraction():
    """
    Called when the hotkey fires:
      1. Capture full screen
      2. OCR it
      3. POST to backend
      4. Show results popup
    """
    print("[Hotkey] Triggered — capturing screen...")

    try:
        # 1. Screen capture
        capturer = ScreenCapture()
        frame    = capturer.capture_frame()          # numpy RGB array

        # 2. OCR
        engine   = get_ocr_engine()
        texts    = engine.extract_text(frame)        # list of strings
        combined = "\n".join(texts)
        print(f"[OCR] Extracted {len(texts)} text blocks.")

        if not combined.strip():
            show_popup(["⚠️ No text detected on screen.\nMake sure the chat panel is visible."])
            return

        # 3. Send to backend
        response = requests.post(
            SERVER_URL,
            json={"chat": combined, "text": combined},
            timeout=10,
        )
        response.raise_for_status()
        data      = response.json()
        questions = data.get("questions", [])
        if isinstance(questions, str):
            questions = [questions]

        print(f"[API] Got {len(questions)} questions.")

        # 4. Show popup (must run on main thread via tkinter)
        show_popup(questions)

    except requests.exceptions.ConnectionError:
        show_popup(["❌ Could not connect to backend.\nMake sure `python server/app.py` is running."])
    except requests.exceptions.Timeout:
        show_popup(["⏱️ Backend took too long to respond.\nTry again in a moment."])
    except Exception as exc:
        show_popup([f"❌ Error: {exc}"])


def show_popup(questions: list[str]):
    """Spawn the popup on its own thread so it doesn't block the tray."""
    threading.Thread(target=lambda: ResultPopup(questions), daemon=True).start()


# ── Tray icon ─────────────────────────────────────────────────────────────────
def make_tray_icon() -> Image.Image:
    """Draw a simple coloured circle icon for the tray."""
    size  = 64
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw  = ImageDraw.Draw(image)
    draw.ellipse([4, 4, size - 4, size - 4], fill="#89b4fa")   # blue dot
    draw.ellipse([20, 20, size - 20, size - 20], fill="#1e1e2e")  # dark centre
    return image


def on_capture_click(icon, item):
    """Tray menu → Capture Now."""
    threading.Thread(target=run_extraction, daemon=True).start()


def on_quit(icon, item):
    """Tray menu → Quit."""
    keyboard.unhook_all()
    icon.stop()


def start_tray():
    menu = pystray.Menu(
        pystray.MenuItem(f"📸 Capture Now  ({HOTKEY.upper()})", on_capture_click),
        pystray.Menu.SEPARATOR,
        pystray.MenuItem("❌ Quit", on_quit),
    )
    icon = pystray.Icon(
        name="QAExtractor",
        icon=make_tray_icon(),
        title="Universal QA Extractor",
        menu=menu,
    )
    return icon


# ── Entry point ───────────────────────────────────────────────────────────────
if __name__ == "__main__":
    print(f"[Tray] Starting Universal QA Extractor tray app...")
    print(f"[Tray] Hotkey: {HOTKEY.upper()}  |  Backend: {SERVER_URL}")
    print(f"[Tray] Right-click the tray icon to capture or quit.\n")

    # Register global hotkey (works even when app is not in focus)
    keyboard.add_hotkey(HOTKEY, lambda: threading.Thread(
        target=run_extraction, daemon=True
    ).start())

    # Start tray (this blocks until quit)
    icon = start_tray()
    icon.run()
