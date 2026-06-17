import json
import random
import os

# Sample data to generate synthetic meeting chats
NAMES = ["Alice", "Bob", "Charlie", "Diana", "Eve", "Frank", "Grace", "Heidi", "Ivan", "Judy", "Mallory"]
GREETINGS = ["Hello everyone!", "Hi team", "Morning!", "Can you hear me?", "Sorry I'm late", "Hey"]
RANDOM_CHAT = [
    "I agree with that point.",
    "Let's move on to the next slide.",
    "My audio is cutting out.",
    "Could someone share the link?",
    "That makes sense.",
    "I'll have to double-check those numbers.",
    "Looks good to me.",
    "Be right back.",
    "Can you zoom in a bit?",
    "Great presentation so far.",
]
QUESTIONS = [
    "What is the deadline for this phase?",
    "Are we going to use PyTorch or TensorFlow?",
    "Who is handling the UI design?",
    "Is this going to be open source?",
    "Will this run on Mac as well?",
    "How are we handling the local database?",
    "Do we need API keys for this?",
    "What's the budget for the cloud infrastructure?",
    "When is the next sync meeting?",
    "Can we skip the frontend for now and focus on backend?",
    "How large is the dataset we are training on?",
    "Will it work without internet?",
]

def generate_synthetic_chat(num_lines=15, num_questions=3):
    chat_log = []
    extracted_questions = []
    
    # Decide which lines will be questions
    question_indices = sorted(random.sample(range(1, num_lines), min(num_questions, num_lines - 1)))
    
    for i in range(num_lines):
        speaker = random.choice(NAMES)
        
        if i == 0:
            msg = random.choice(GREETINGS)
        elif i in question_indices:
            msg = random.choice(QUESTIONS)
            extracted_questions.append(msg)
        else:
            msg = random.choice(RANDOM_CHAT)
            
        chat_log.append(f"{speaker}: {msg}")
        
    chat_text = "\n".join(chat_log)
    summary_text = "\n".join([f"- {q}" for q in extracted_questions])
    if not summary_text:
        summary_text = "No questions asked."
        
    return chat_text, summary_text

def generate_dataset(num_samples=5000, output_file="data.jsonl"):
    print(f"Generating {num_samples} synthetic meeting chats...")
    
    # Ensure directory exists
    os.makedirs(os.path.dirname(output_file), exist_ok=True)
    
    with open(output_file, 'w', encoding='utf-8') as f:
        for _ in range(num_samples):
            chat, summary = generate_synthetic_chat(
                num_lines=random.randint(5, 20),
                num_questions=random.randint(0, 4)
            )
            data_point = {
                "input": chat,
                "target": summary
            }
            f.write(json.dumps(data_point) + "\n")
            
    print(f"Dataset saved to {output_file}")

if __name__ == "__main__":
    # Force output to the D: drive .cache folder to save space
    PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    output_path = os.path.join(PROJECT_ROOT, ".cache", "dataset", "train_data.jsonl")
    generate_dataset(5000, output_path)
