import os
import json
import torch
from torch.utils.data import Dataset, DataLoader
from transformers import T5Tokenizer, T5ForConditionalGeneration, AdamW

# Set environment variables to force local cache
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE_DIR = os.path.join(PROJECT_ROOT, ".cache")
os.environ["HF_HOME"] = os.path.join(CACHE_DIR, "huggingface")
os.environ["TORCH_HOME"] = os.path.join(CACHE_DIR, "torch")

class ChatDataset(Dataset):
    def __init__(self, jsonl_file, tokenizer, max_length=512):
        self.tokenizer = tokenizer
        self.max_length = max_length
        self.data = []
        with open(jsonl_file, 'r', encoding='utf-8') as f:
            for line in f:
                self.data.append(json.loads(line))

    def __len__(self):
        return len(self.data)

    def __getitem__(self, idx):
        item = self.data[idx]
        input_text = "extract questions: " + item['input']
        target_text = item['target']

        input_tokenized = self.tokenizer(
            input_text, max_length=self.max_length, padding='max_length', truncation=True, return_tensors="pt"
        )
        target_tokenized = self.tokenizer(
            target_text, max_length=self.max_length, padding='max_length', truncation=True, return_tensors="pt"
        )

        return {
            "input_ids": input_tokenized.input_ids.squeeze(),
            "attention_mask": input_tokenized.attention_mask.squeeze(),
            "labels": target_tokenized.input_ids.squeeze()
        }

def train_model():
    print("Starting Custom ML Model Training Pipeline...")
    data_path = os.path.join(CACHE_DIR, "dataset", "train_data.jsonl")
    
    if not os.path.exists(data_path):
        print(f"Error: Dataset not found at {data_path}. Run dataset.py first.")
        return

    # Use a tiny base model for fast local training
    model_name = "t5-small"
    print(f"Downloading/Loading base model {model_name} into {CACHE_DIR}...")
    tokenizer = T5Tokenizer.from_pretrained(model_name)
    model = T5ForConditionalGeneration.from_pretrained(model_name)

    dataset = ChatDataset(data_path, tokenizer)
    # Use a small batch size to ensure it fits in memory
    dataloader = DataLoader(dataset, batch_size=4, shuffle=True)

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Training on device: {device}")
    model.to(device)

    optimizer = AdamW(model.parameters(), lr=5e-5)

    epochs = 1 # Keep it to 1 epoch for prototype speed
    model.train()

    print("Beginning Training Loop...")
    for epoch in range(epochs):
        total_loss = 0
        for i, batch in enumerate(dataloader):
            optimizer.zero_grad()
            
            input_ids = batch['input_ids'].to(device)
            attention_mask = batch['attention_mask'].to(device)
            labels = batch['labels'].to(device)

            outputs = model(input_ids=input_ids, attention_mask=attention_mask, labels=labels)
            loss = outputs.loss
            loss.backward()
            optimizer.step()
            
            total_loss += loss.item()
            
            if i % 50 == 0:
                print(f"Epoch {epoch+1} | Batch {i}/{len(dataloader)} | Loss: {loss.item():.4f}")

    # Save the custom trained model locally
    output_dir = os.path.join(CACHE_DIR, "custom_model")
    os.makedirs(output_dir, exist_ok=True)
    model.save_pretrained(output_dir)
    tokenizer.save_pretrained(output_dir)
    print(f"Custom Model successfully trained and saved to {output_dir}")

if __name__ == "__main__":
    train_model()
