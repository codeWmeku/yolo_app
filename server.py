from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.responses import JSONResponse
import requests
import tkinter as tk
from tkinter import simpledialog, messagebox, filedialog
from urllib.parse import quote
import threading
import time
import cv2
import numpy as np
from PIL import Image
import io
import base64
import os
from ultralytics import YOLO
import torch

# FastAPI server
app = FastAPI()

OLLAMA_API_URL = "http://localhost:11434/api/generate"

# Load YOLO model (you can use yolov8n.pt, yolov8s.pt, yolov8m.pt, yolov8l.pt, yolov8x.pt)
try:
    model = YOLO('yolov8n.pt')  # This will download the model if not present
    print("YOLO model loaded successfully!")
except Exception as e:
    print(f"Error loading YOLO model: {e}")
    model = None

@app.get("/ask")
def ask_question(q: str):
    """
    Handles GET requests from Flutter and Tkinter.
    Sends the user's question to Ollama and returns a response.
    """
    data = {
        "model": "mistral",  # Make sure this model is installed in Ollama
        "prompt": q,
        "stream": False
    }
    
    try:
        response = requests.post(OLLAMA_API_URL, json=data, timeout=30)
        
        if response.status_code == 200:
            ollama_response = response.json()
            if "response" in ollama_response:
                return {"response": ollama_response["response"]}
            else:
                return {"response": str(ollama_response)}
        else:
            print(f"Ollama API error: {response.status_code}")
            print(f"Response: {response.text}")
            return {"response": f"Ollama API error: {response.status_code}"}
    except requests.exceptions.Timeout:
        return {"response": "Request timed out. Please try again."}
    except requests.exceptions.ConnectionError:
        return {"response": "Cannot connect to Ollama. Make sure Ollama is running on localhost:11434"}
    except Exception as e:
        print(f"Error: {e}")
        return {"response": f"Server error: {str(e)}"}

@app.post("/detect-objects")
async def detect_objects(file: UploadFile = File(...)):
    """
    Detects objects in uploaded image using YOLO model
    """
    if model is None:
        raise HTTPException(status_code=500, detail="YOLO model not loaded")
    
    if not file.content_type.startswith('image/'):
        raise HTTPException(status_code=400, detail="File must be an image")
    
    try:
        # Read image file
        contents = await file.read()
        image = Image.open(io.BytesIO(contents))
        
        # Convert to OpenCV format
        opencv_image = cv2.cvtColor(np.array(image), cv2.COLOR_RGB2BGR)
        
        # Run YOLO detection
        results = model(opencv_image)
        
        # Process results
        detections = []
        annotated_image = opencv_image.copy()
        
        for result in results:
            boxes = result.boxes
            if boxes is not None:
                for box in boxes:
                    # Get bounding box coordinates
                    x1, y1, x2, y2 = box.xyxy[0]
                    confidence = box.conf[0]
                    class_id = int(box.cls[0])
                    class_name = model.names[class_id]
                    
                    # Only include detections with confidence > 0.5
                    if confidence > 0.5:
                        detections.append({
                            "class": class_name,
                            "confidence": float(confidence),
                            "bbox": {
                                "x1": float(x1),
                                "y1": float(y1),
                                "x2": float(x2),
                                "y2": float(y2)
                            }
                        })
                        
                        # Draw bounding box on image
                        cv2.rectangle(annotated_image, 
                                    (int(x1), int(y1)), 
                                    (int(x2), int(y2)), 
                                    (0, 255, 0), 2)
                        
                        # Add label
                        label = f"{class_name}: {confidence:.2f}"
                        cv2.putText(annotated_image, label, 
                                  (int(x1), int(y1) - 10), 
                                  cv2.FONT_HERSHEY_SIMPLEX, 0.5, 
                                  (0, 255, 0), 2)
        
        # Convert annotated image to base64
        _, buffer = cv2.imencode('.jpg', annotated_image)
        annotated_image_base64 = base64.b64encode(buffer).decode('utf-8')
        
        return JSONResponse({
            "success": True,
            "detections": detections,
            "total_objects": len(detections),
            "annotated_image": annotated_image_base64
        })
        
    except Exception as e:
        print(f"Detection error: {e}")
        raise HTTPException(status_code=500, detail=f"Detection failed: {str(e)}")

@app.get("/")
def health_check():
    return {
        "status": "Server is running!", 
        "message": "FastAPI Ollama Bridge with Object Detection is active",
        "yolo_loaded": model is not None
    }

@app.get("/test-ollama")
def test_ollama():
    try:
        response = requests.get("http://localhost:11434/api/tags", timeout=5)
        if response.status_code == 200:
            models = response.json()
            return {"status": "Ollama is running", "models": models}
        else:
            return {"status": "Ollama not responding", "error": response.status_code}
    except Exception as e:
        return {"status": "Cannot connect to Ollama", "error": str(e)}

def tkinter_app():
    root = tk.Tk()
    root.title("Object Detection & Chat Test")
    root.geometry("400x300")
    
    def test_chat():
        user_input = simpledialog.askstring("Ollama Chat", "Ask a question:")
        if user_input:
            try:
                response = requests.get(f"http://192.168.100.35:8000/ask?q={quote(user_input)}", timeout=10)
                if response.status_code == 200:
                    answer = response.json().get("response", "No response")
                else:
                    answer = f"Error: HTTP {response.status_code}"
            except Exception as e:
                answer = f"Connection error: {str(e)}"
            messagebox.showinfo("Chat Response", answer)
    
    def test_detection():
        file_path = filedialog.askopenfilename(
            title="Select an image for object detection",
            filetypes=[("Image files", "*.jpg *.jpeg *.png *.bmp *.gif")]
        )
        
        if file_path:
            try:
                with open(file_path, 'rb') as f:
                    files = {'file': f}
                    response = requests.post("http://192.168.100.35:8000/detect-objects", files=files, timeout=30)
                
                if response.status_code == 200:
                    result = response.json()
                    objects = result.get('detections', [])
                    total = result.get('total_objects', 0)
                    
                    if total > 0:
                        object_list = "\n".join([f"- {obj['class']} ({obj['confidence']:.2f})" for obj in objects])
                        message = f"Found {total} objects:\n{object_list}"
                    else:
                        message = "No objects detected"
                    
                    messagebox.showinfo("Detection Result", message)
                else:
                    messagebox.showerror("Error", f"Detection failed: {response.status_code}")
                    
            except Exception as e:
                messagebox.showerror("Error", f"Detection error: {str(e)}")
    
    # Create buttons
    chat_btn = tk.Button(root, text="Test Chat", command=test_chat, width=20, height=2)
    chat_btn.pack(pady=10)
    
    detect_btn = tk.Button(root, text="Test Object Detection", command=test_detection, width=20, height=2)
    detect_btn.pack(pady=10)
    
    info_label = tk.Label(root, text="Server running on http://192.168.100.35:8000", wraplength=300)
    info_label.pack(pady=20)
    
    quit_btn = tk.Button(root, text="Quit", command=root.quit, width=20, height=2)
    quit_btn.pack(pady=10)
    
    root.mainloop()

if __name__ == "__main__":
    print("Starting FastAPI Server with Object Detection...")
    print("Installing required packages if needed...")
    
    # Install required packages
    try:
        import ultralytics
        import torch
        print("✓ All packages are installed")
    except ImportError as e:
        print(f"Missing package: {e}")
        print("Please install: pip install ultralytics torch opencv-python pillow")
    
    print("Server will run on http://0.0.0.0:8000")
    print("Your Flutter app should connect to http://192.168.100.35:8000")
    
    # Start Tkinter in a separate thread
    threading.Thread(target=tkinter_app, daemon=True).start()
    
    # Start FastAPI server
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)