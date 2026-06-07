# Offline Facial Authentication System Documentation

## 1. Architecture Overview

The system is a fully unique, robust, and **completely OFFLINE** facial authentication application built with Flutter and Dart. It leverages high-performance ONNX models executed natively on-device using the `onnxruntime_v2` engine.

### Core Stack:
- **Frontend**: Flutter (Dart)
- **Inference Engine**: ONNX Runtime (Mobile)
- **Local Storage**: `flutter_secure_storage` (Hardware-backed AES encryption)
- **Image Processing**: Custom pure-Dart YUV-to-RGB conversion with biometric enhancement kernels.

---

## 2. Methodology & Pipeline

The authentication pipeline is divided into three distinct layers to ensure both security and accuracy.

### Layer A: Face Localization (YuNet)
- **Model**: `face_detection_yunet_2023mar.onnx`
- **Input**: 640x640 Planar BGR matrix.
- **Process**:
    - Raw `CameraImage` (YUV420) is preprocessed directly into a BGR buffer.
    - **Letterboxing** is applied to maintain the natural aspect ratio of the user's face, preventing "stretching" which degrades recognition accuracy.
    - **Decoding**: The system decodes 12 raw output tensors (classification, objectness, bbox, and keypoints across three strides: 8, 16, and 32).
- **Output**: Bounding box coordinates and confidence score.

### Layer B: Spoofing Mitigation (MiniFASNet)
- **Model**: `best_model.onnx`
- **Input**: 128x128 normalized RGB crop.
- **Process**:
    - The detected face is cropped and resized using Nearest-Neighbor interpolation for speed.
    - A **Softmax** function is applied to the output logits to determine the probability of a "Real" face vs. a "Fake" (photo/video) face.
    - The system requires a high confidence (> 0.6) to proceed to identity validation.

### Layer C: Identity Validation (EdgeFace)
- **Model**: `edgeface_xs_gamma_06.onnx`
- **Input**: 112x112 RGB Planar crop with biometric enhancement.
- **Biometric Enhancement**:
    - **Histogram Stretching**: Contrast is boosted by 1.5x to reveal facial features in poor lighting.
    - **Sharpening**: A 3x3 Laplacian kernel is applied to restore detail lost to camera blur.
- **Comparison**:
    - Generates a 512-dimension feature vector (embedding).
    - **Best-Match Search**: The system scans the entire local database using **Cosine Similarity**.
    - Identity is confirmed only if the best match score exceeds the threshold (Default: 0.65).

---

## 3. Integration & Implementation Steps

### Asset Configuration
Models are stored in `assets/models/` and registered in `pubspec.yaml`. They are loaded as byte buffers into `OrtSession` during engine initialization.

### Memory Management
To prevent Out-Of-Memory (OOM) crashes during high-speed camera streaming:
- All `OrtValue` tensors are wrapped in `try-finally` blocks.
- Explicit `.release()` calls are made immediately after inference.
- **Isolate-like Throttling**: The stream listener drops incoming frames until the previous evaluation loop is complete.

### Android-Specific Hardening
- **minSdkVersion 24**: Required for modern hardware image stream allocations.
- **NDK 28.2.13676358**: Ensures compatibility with the latest ONNX Runtime native binaries.
- **Packaging Options**: Configured `pickFirst` for multi-ABI `.so` files to prevent build conflicts.

---

## 4. Model Benchmarks

| Phase | Model | Input Size | Average Latency (Mid-Range Device) |
| :--- | :--- | :--- | :--- |
| **Detection** | YuNet | 640x640 | 180ms |
| **Liveness** | MiniFASNet | 128x128 | 45ms |
| **Recognition** | EdgeFace | 112x112 | 60ms |
| **Total Pipeline** | - | - | **~285ms** |

*Note: Benchmarks represent CPU-only execution for maximum stability.*

---

## 5. Security Protocol

1.  **Zero Network Footprint**: No biometric data ever leaves the device.
2.  **Encrypted Persistence**: Face embeddings are stored as JSON-serialized double arrays inside the Android Keystore / iOS Keychain.
3.  **Liveness Enforcement**: The system strictly denies recognition attempts if the MiniFASNet confidence is low, preventing simple bypasses with digital photos.
