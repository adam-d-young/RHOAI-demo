import tensorflow as tf
import os

print("--- FINAL CONFIG CHECK ---")
print(f"LD_LIBRARY_PATH: {os.environ.get('LD_LIBRARY_PATH', 'Not Set')}")
# Expect: /opt/app-root/src/driver-override

print("\n--- GPU HARDWARE CHECK ---")
gpus = tf.config.list_physical_devices('GPU')

if len(gpus) > 0:
    print(f"VICTORY! Found {len(gpus)} GPU(s)")
    print(f"   Name: {gpus[0].name}")

    with tf.device('/GPU:0'):
        a = tf.constant([[1.0, 2.0], [3.0, 4.0]])
        b = tf.constant([[1.0, 1.0], [0.0, 1.0]])
        c = tf.matmul(a, b)
        print("   Matrix Result: Success")
else:
    print("FAILED - No GPUs found.")
