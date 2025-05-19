
from fastapi import FastAPI
import requests
import tkinter as tk
from tkinter import simpledialog, messagebox

# FastAPI server
app = FastAPI()

OLLAMA_API_URL = "http://localhost:11434/api/generate"

@app.get("/ask")
def ask_question(q: str):
    """
    Handles GET requests from Flutter and Tkinter.
    Sends the user's question to Ollama and returns a response.
    """
    data = {
        "model": "mistral",  # Change to any Ollama model
        "prompt": q,
        "stream": False
    }
    
    response = requests.post(OLLAMA_API_URL, json=data)
    
    if response.status_code == 200:
        ollama_response = response.json()
        # The Ollama API returns the text in the 'response' field
        if "response" in ollama_response:
            return {"response": ollama_response["response"]}
        else:
            # Fallback in case the response structure is different
            return {"response": str(ollama_response)}
    else:
        return {"response": "Failed to get a response from Ollama."}

# Tkinter GUI for local testing
def tkinter_app():
    root = tk.Tk()
    root.withdraw()  # Hide main window
    
    while True:
        user_input = simpledialog.askstring("Ollama Chat", "Ask a question:")
        
        if user_input is None:  # User canceled
            break
        
        response = requests.get(f"http://l192.168.100.35/ask?q={user_input}")
        
        if response.status_code == 200:
            answer = response.json().get("response", "No response")
        else:
            answer = "Error: Could not fetch response."
        
        messagebox.showinfo("Response", answer)

# Run Tkinter in a separate thread (optional)
if __name__ == "__main__":
    import threading
    threading.Thread(target=tkinter_app).start()
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
