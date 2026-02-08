import tensorflow as tf
import os
import boto3
import shutil

# --- CONFIGURATION ---
MODEL_NAME = "demo-model"     # Name of your model
MODEL_VERSION = "1"           # Triton requires a numeric version folder
BUCKET_PREFIX = "production"  # The folder inside your bucket where models live
LOCAL_TEMP_DIR = "temp_export"

# --- 1. Clean up previous local runs ---
if os.path.exists(LOCAL_TEMP_DIR):
    shutil.rmtree(LOCAL_TEMP_DIR)

# --- 2. Create the Model ---
print("Creating model...")
inputs = tf.keras.Input(shape=(5,))
x = tf.keras.layers.Dense(10, activation='relu')(inputs)
outputs = tf.keras.layers.Dense(1, activation='sigmoid')(x)
model = tf.keras.Model(inputs=inputs, outputs=outputs)

# --- 3. Export as TensorFlow SavedModel ---
# TensorFlow exports produce these files:
#   saved_model.pb  -- the computation graph (layers, ops, shapes) in Protocol Buffer format
#   fingerprint.pb  -- hash of the model for integrity/versioning
#   variables/      -- the trained weights (what the model actually learned)
#     variables.data-00000-of-00001  -- weight values (can be GBs for large models)
#     variables.index               -- index mapping variable names to data offsets
#
# Triton expects: {model_name}/{version}/model.savedmodel/saved_model.pb
# So the S3 layout will be: production/demo-model/1/model.savedmodel/saved_model.pb
export_path = os.path.join(LOCAL_TEMP_DIR, MODEL_VERSION, "model.savedmodel")
model.export(export_path)
print(f"Model exported locally to: {os.path.abspath(export_path)}")

# --- 4. Generate Triton config.pbtxt ---
# Triton needs this file at the model root (next to the version folder)
# to know which backend to use and the tensor shapes.
#   name       -- must match the model directory name
#   backend    -- "tensorflow" tells Triton to load it as a SavedModel
#   input/output -- tensor names, types, and dimensions
config_content = f"""name: "{MODEL_NAME}"
platform: "tensorflow_savedmodel"
input [{{ name: "keras_tensor", data_type: TYPE_FP32, dims: [5] }}]
output [{{ name: "output_0", data_type: TYPE_FP32, dims: [1] }}]
"""
config_path = os.path.join(LOCAL_TEMP_DIR, "config.pbtxt")
with open(config_path, "w") as f:
    f.write(config_content)
print(f"Triton config written to: {os.path.abspath(config_path)}")

# --- 5. Upload to MinIO (S3) with Prefix ---
print("\nUploading to S3...")
s3_endpoint = os.environ.get('AWS_S3_ENDPOINT')
access_key = os.environ.get('AWS_ACCESS_KEY_ID')
secret_key = os.environ.get('AWS_SECRET_ACCESS_KEY')
bucket_name = "models"

s3 = boto3.client(
    's3',
    endpoint_url=s3_endpoint,
    aws_access_key_id=access_key,
    aws_secret_access_key=secret_key,
    verify=False
)

# Walk the local directory and upload to the specific S3 folder
for root, dirs, files in os.walk(LOCAL_TEMP_DIR):
    for file in files:
        local_path = os.path.join(root, file)

        # Calculate the relative path (e.g., "1/saved_model.pb")
        relative_path = os.path.relpath(local_path, start=LOCAL_TEMP_DIR)

        # Construct the full S3 path (e.g., "production/demo-model/1/saved_model.pb")
        s3_path = os.path.join(BUCKET_PREFIX, MODEL_NAME, relative_path)

        print(f"Uploading: {s3_path}")
        s3.upload_file(local_path, bucket_name, s3_path)

print(f"\nUpload Complete!")
print(f"Your Model Path for Serving is: {BUCKET_PREFIX}/{MODEL_NAME}")
