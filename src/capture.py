import mss
import mss.tools
import numpy as np
from PIL import Image

class ScreenCapture:
    def __init__(self):
        self.sct = mss.mss()
        self.monitor = self.sct.monitors[1]  # Capture primary monitor by default

    def set_capture_region(self, top, left, width, height):
        """Set a specific region of the screen to capture (useful for chat boxes)."""
        self.monitor = {"top": top, "left": left, "width": width, "height": height}

    def capture_frame(self):
        """Captures a single frame of the screen and returns a numpy array (RGB format)."""
        sct_img = self.sct.grab(self.monitor)
        # Convert to PIL Image
        img = Image.frombytes("RGB", sct_img.size, sct_img.bgra, "raw", "BGRX")
        # Convert to numpy array for EasyOCR
        return np.array(img)

    def capture_and_save(self, output_filename="capture.png"):
        """Captures and saves a frame for debugging purposes."""
        sct_img = self.sct.grab(self.monitor)
        mss.tools.to_png(sct_img.rgb, sct_img.size, output=output_filename)
        print(f"Saved capture to {output_filename}")
