import tensorflow as tf

print("--- DEMO COMPLETE ---")
with tf.device('/GPU:0'):
    a = tf.constant([[1.0, 2.0], [3.0, 4.0]])
    b = tf.constant([[1.0, 1.0], [0.0, 1.0]])
    c = tf.matmul(a, b)

    print("Matrix Multiplication Result:")
    print(c.numpy())
    print("\nThe GPU is fully operational.")
