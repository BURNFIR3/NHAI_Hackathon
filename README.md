# NHAI_Hackathon

## Offline Facial Authentication System

This repository presents a privacy-first Flutter app built to authenticate users offline on Android.
It uses on-device ONNX inference to detect faces, verify liveness, and validate identity without sending biometric data to the cloud.

## System Architecture

The solution is structured around a three-stage inference pipeline:

1. **YuNet face detection** (`face_detection_yunet_2023mar.onnx`)
   - Detects face bounding boxes and 5-point landmarks.
   - Provides the first pass of face localization and tracking.
2. **MiniFASNet liveness verification** (`best_model.onnx`)
   - Evaluates whether the detected face belongs to a live person.
   - Prevents spoofing from printed photos or screen replay attacks.
3. **EdgeFace recognition** (`edgeface_xs_gamma_06.onnx`)
   - Extracts a compact embedding for identity matching.
   - Compares live embeddings to registered templates on device.

### Implementation details

- `lib/onnx_engine.dart` loads all ONNX sessions with `onnxruntime_v2`.
- Image preprocessing is tailored per model: RGB planar for EdgeFace, normalized face crops for YuNet, and 128x128 liveness patches for MiniFASNet.
- The app architecture is Flutter-driven with a native Android build target.
- Face authentication is executed entirely on the device, so network access is optional.

## Android APK Download

If a prebuilt Android package is published, download the latest APK from:

- `https://github.com/BURNFIR3/NHAI_Hackathon/releases/latest`

### Build locally

```bash
flutter pub get
flutter build apk --release
```

The generated APK can be found at:

- `build/app/outputs/flutter-apk/app-release.apk`

Install to a connected device with:

```bash
flutter install
```

## Benchmarks

| Stage | Model | Input | Approximate latency |
|---|---|---|---|
| Detection | YuNet | 640x640 | 180 ms |
| Liveness | MiniFASNet | 128x128 | 45 ms |
| Recognition | EdgeFace | 112x112 | 60 ms |

> These numbers are typical device-level CPU inference estimates and are useful for comparing model performance.

## Model Licenses

This project includes the following external model assets. The license files are included in the repository root.

- `assets/models/face_detection_yunet_2023mar.onnx` — **MIT License** (`LICENSE_YUNET.md`)
- `assets/models/best_model.onnx` — **Apache License 2.0** (`LICENSE_MINIFASNET.md`)
- `assets/models/edgeface_xs_gamma_06.onnx` — **BSD 3-Clause License** (`LICENSE_EDGEFACE.md`)

## Usage

```bash
git clone https://github.com/BURNFIR3/NHAI_Hackathon.git
cd NHAI_Hackathon
flutter pub get
flutter run
```

## Notes

- This repository is designed for offline facial authentication.
- All biometric inference is performed locally on the device.
- iOS support is not yet integrated in this version and will require additional platform work.

## Future Direction

See `FUTURE_IMPROVEMENTS.md` for planned features such as AWS syncing, iOS support, and secure cloud backup.

## Sources

- YuNet face detector: OpenCV Zoo / MIT
- MiniFASNet anti-spoofing: Apache 2.0
- EdgeFace recognition: BSD 3-Clause
