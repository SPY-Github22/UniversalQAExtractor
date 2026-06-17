import easyocr

class OCREngine:
    def __init__(self, languages=['en']):
        # Initialize EasyOCR reader. 
        # Note: The first time this runs, it will download the models to the local machine.
        # gpu=False is a safe default, but easyocr will use CUDA if available.
        print("Initializing Local OCR Engine...")
        self.reader = easyocr.Reader(languages, gpu=True)

    def extract_text(self, image_np_array):
        """
        Extracts text from a numpy image array.
        Returns a list of strings representing the detected text blocks.
        """
        results = self.reader.readtext(image_np_array, detail=0) # detail=0 returns just the text
        return results
