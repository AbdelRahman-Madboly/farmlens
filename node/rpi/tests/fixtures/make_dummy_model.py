"""
Generate tests/fixtures/dummy_classifier.tflite.

The model is a tiny randomly initialised network (no training, no data) with
the input and output shapes the node expects: [1, 32, 32, 3] float32 in,
[1, 18] softmax out. It exists only so the TFLite code path can be tested.
Its predictions are meaningless.

Needs TensorFlow, which is not a project dependency:
    pip install tensorflow-cpu
    python tests/fixtures/make_dummy_model.py
"""
import os

import tensorflow as tf

N_CLASSES = 18  # len(config.DISEASE_CLASSES)

tf.keras.utils.set_random_seed(0)
model = tf.keras.Sequential([
    tf.keras.Input(shape=(32, 32, 3)),
    tf.keras.layers.Conv2D(4, 3, activation="relu"),
    tf.keras.layers.GlobalAveragePooling2D(),
    tf.keras.layers.Dense(N_CLASSES, activation="softmax"),
])

converter = tf.lite.TFLiteConverter.from_keras_model(model)
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "dummy_classifier.tflite")
with open(out, "wb") as f:
    f.write(converter.convert())
print("wrote", out, os.path.getsize(out), "bytes")
