import os
from flask import Flask, request, jsonify
from flask_cors import CORS
import torch
from transformers import T5Tokenizer, T5ForConditionalGeneration

app = Flask(__name__)
CORS(app)  # Allow the Chrome extension to hit this endpoint

# Force caches to D: Drive
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE_DIR = os.path.join(PROJECT_ROOT, ".cache")
os.environ["HF_HOME"] = os.path.join(CACHE_DIR, "huggingface")
os.environ["TORCH_HOME"] = os.path.join(CACHE_DIR, "torch")

# Load our custom trained model globally
MODEL_DIR = os.path.join(CACHE_DIR, "custom_model")
try:
    print(f"Loading custom trained model from {MODEL_DIR}...")
    tokenizer = T5Tokenizer.from_pretrained(MODEL_DIR)
    model = T5ForConditionalGeneration.from_pretrained(MODEL_DIR)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model.to(device)
    model.eval()
    print("Model loaded successfully.")
except Exception as e:
    print(f"Warning: Custom model not found in {MODEL_DIR}. Did you run ml/train.py first?")
    tokenizer, model, device = None, None, None

@app.route('/extract', methods=['POST'])
def extract_questions():
    if not model or not tokenizer:
        return jsonify({"error": "Model not trained yet. Run ml/train.py first."}), 500

    data = request.json
    chat_text = data.get('chat', '')
    
    if not chat_text:
        return jsonify({"questions": "No chat provided."})

    input_text = "extract questions: " + chat_text
    input_ids = tokenizer.encode(input_text, return_tensors="pt", max_length=512, truncation=True).to(device)

    # Generate summary/questions
    with torch.no_grad():
        outputs = model.generate(input_ids, max_length=150, num_beams=4, early_stopping=True)
    
    extracted_questions = tokenizer.decode(outputs[0], skip_special_tokens=True)
    
    # Split by newlines or dashes if the model output them as a list
    questions_list = [q.strip() for q in extracted_questions.split('-') if q.strip()]
    if not questions_list:
        questions_list = [extracted_questions]

    return jsonify({"questions": questions_list})

if __name__ == '__main__':
    print("Starting Universal QA Extractor API on port 5000...")
    app.run(port=5000, debug=False)
