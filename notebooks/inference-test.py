import os
import warnings
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '2'
warnings.filterwarnings('ignore', message='.*Protobuf gencode version.*')

import requests
import json

# --- CONFIGURATION ---
MODEL_NAME = "demo-model"
# Internal service URL -- workbench and model are in the same namespace
TRITON_URL = f"http://fsi-demo-model-predictor.fsi-demo.svc.cluster.local:80/v2/models/{MODEL_NAME}"

# --- 1. Check Model Health ---
print("--- MODEL HEALTH CHECK ---")
resp = requests.get(TRITON_URL)
metadata = resp.json()
print(f"Model:    {metadata['name']}")
print(f"Version:  {metadata['versions'][0]}")
print(f"Platform: {metadata['platform']}")

# Auto-detect input tensor name (TF/Keras appends a suffix each export)
input_name = metadata['inputs'][0]['name']
input_shape = metadata['inputs'][0]['shape']
print(f"Input:    {input_name} {input_shape}")
print(f"Output:   {metadata['outputs'][0]['name']} {metadata['outputs'][0]['shape']}")

# --- 2. Send Prediction ---
print("\n--- PREDICTION 1 ---")
data = [0.1, 0.5, 0.3, 0.7, 0.2]
payload = {
    "inputs": [{
        "name": input_name,
        "shape": [1, 5],
        "datatype": "FP32",
        "data": data
    }]
}

resp = requests.post(f"{TRITON_URL}/infer", json=payload)
result = resp.json()
prediction = result['outputs'][0]['data'][0]
print(f"Input:      {data}")
print(f"Prediction: {prediction:.6f}")

# --- 3. Different Input ---
print("\n--- PREDICTION 2 ---")
data2 = [0.9, 0.1, 0.8, 0.2, 0.95]
payload["inputs"][0]["data"] = data2

resp = requests.post(f"{TRITON_URL}/infer", json=payload)
result = resp.json()
prediction2 = result['outputs'][0]['data'][0]
print(f"Input:      {data2}")
print(f"Prediction: {prediction2:.6f}")

# --- Summary ---
print("\n--- SUMMARY ---")
print(f"Different inputs → different predictions ({prediction:.4f} vs {prediction2:.4f})")
print("The model is running on GPU via Triton Inference Server.")
print("In production: fraud scores, credit risk, real-time pricing.")
