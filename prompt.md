To make sure your new project compiles completely error-free on the first attempt and looks completely unique, we will re-architect the code.

Based on the `robert008-flutter_face_kit` reference you provided, that specific implementation heavily utilizes native Android C++ code compilation (`detect_utils.cpp` inside the `android/` directory) which makes it **Android-only** and completely missing the required iOS build files out-of-the-box.

To solve this, support **both Android and iOS**, add **MiniFASNet anti-spoofing**, and bypass the native C++ compilation traps that cause Gradle errors, this master prompt moves the entire AI processing pipeline to **Dart using pure `onnxruntime_flutter` bindings**.

Create a file named `prompt.md` in your new Android Studio directory, copy the text below into it, and feed it to your AI coding assistant (Cursor, Claude, or Copilot).

---

```markdown
# System Objective & Identity
You are a Principal Mobile Systems Engineer specializing in cross-platform Flutter engines and native FFI ONNX Runtime integrations. Your task is to generate a fully unique, robust, completely OFFLINE facial authentication prototype application named "placeholdernhai".

The architecture must be pure Flutter/Dart-centric, ensuring seamless cross-functional deployment on BOTH Android and iOS without requiring custom native C++ Android-NDK or iOS Objective-C compilation chains.

# Project Constraints & Assets
- Framework Core: Flutter Stable (Supporting Android 8.0+ / iOS 12+)
- Inference Engine: `onnxruntime_flutter` (Natively executes ONNX weights on CPU execution threads cross-platform)
- Local Vault Architecture: `flutter_secure_storage` (Hardware-isolated AES encryption)
- Exact Application Asset File Registry:
    1. Face Detection: `assets/models/face_detection_yunet_2023mar.onnx`
    2. Face Recognition: `assets/models/edgeface_xs_gamma_06.onnx`
    3. Liveness/Anti-Spoofing: `assets/models/best_model.onnx`

---

# Functional Scope & UI/UX Sequence

The interface must be styled with a clean, dark-futuristic theme. It must strictly expose only two modular flows: Registration and Verification.

## Flow 1: Secure Facial Registration (Sign-Up)
- UI requests a text ID identifier.
- Opens a full-screen camera viewport streaming native image frame matrices.
- **Processing Flow:**
    1. The frame buffer is transformed into an input tensor.
    2. `face_detection_yunet_2023mar.onnx` runs to detect bounding box coordinates.
    3. The cropped facial tensor is immediately forwarded to `edgeface_xs_gamma_06.onnx` to generate a lightweight structural array descriptor.
- **Persistence:** The generated signature is serialized and committed to `flutter_secure_storage` matched against the profile name.
- Terminates camera controllers and displays a success notification.

## Flow 2: Live Dual-Layer Recognition (Log-In)
- Opens the live camera framework stream.
- **Dynamic Human Interactivity Directive (The Verification Phase):**
    - The screen displays an active text banner prompting the user to complete randomized physical movements to verify liveness (e.g., "Please blink your eyes now" or "Slowly turn your head slightly").
- **Real-Time On-Device Loop Budget (< 1 Second Synchronous Pipeline):**
    1. **Layer A (Localization):** Track the face box array using `face_detection_yunet_2023mar.onnx`.
    2. **Layer B (Spoofing Mitigation):** Extract the facial frame patch and pass it to `best_model.onnx` (MiniFASNet). The network must return a "Real Human Face" classification metric passing a high confidence threshold before letting the logic proceed.
    3. **Layer C (Identity Validation):** Extract the live face embedding matrix using `edgeface_xs_gamma_06.onnx`. Pull the referenced template signature from `flutter_secure_storage`, decode it, and compute the Cosine Similarity calculation entirely inside Dart code.
- **Termination State:** When Liveness == Valid AND Cosine Similarity passes your matching threshold, trigger a haptic pulse, verify identity, and cleanly dispose of active camera streams.

---

# Anti-Crash Guardrails & Structural Changes

To ensure this codebase looks entirely custom-written and avoids all native mobile workspace crashes, enforce the following parameters across all generated files:

### 1. Build Layer Configurations (`android/app/build.gradle`)
- Enforce `minSdkVersion 24` to comply with modern hardware image stream allocations.
- Append a clean packaging options block to suppress multi-ABI duplicate binary conflicts:
```groovy
android {
    ...
    packagingOptions {
        pickFirst 'lib/arm64-v8a/libonnxruntime.so'
        pickFirst 'lib/armeabi-v7a/libonnxruntime.so'
        pickFirst 'lib/x86/libonnxruntime.so'
        pickFirst 'lib/x86_64/libonnxruntime.so'
    }
}

```

### 2. Apple iOS Configurations (`ios/Runner/Info.plist`)

* Include the explicit camera hardware access parameter strings to prevent immediate startup crashes on iOS testing environments:

```xml
<key>NSCameraUsageDescription</key>
<string>This application requires offline camera access to compute structural facial authentication benchmarks locally on your device.</string>

```

### 3. Native Allocation Disposal (`lib/onnx_engine.dart`)

* To prevent immediate platform out-of-memory memory exhaustion crashes when parsing live image streams, every allocated `OrtValue` or execution buffer tensor must call `.release()` inside a try-finally block on every single frame loop iteration.

---

# Mandatory Project Layout & Outputs Required

Generate the complete, highly polished implementation split across these explicit file layers:

1. `pubspec.yaml` (Complete package specifications containing camera, secure storage, and onnxruntime configurations with the exact asset model trees).
2. `android/app/build.gradle` (The fortified build parameters).
3. `ios/Runner/Info.plist` (iOS execution settings).
4. `lib/onnx_engine.dart` (The core computing module managing `OrtSession` allocations, pixel matrix preprocessing, and cosine mathematical checks).
5. `lib/main.dart` (The dark-themed interface managing state views, interactive text prompts, and camera streaming loops).

```

***

### 💡 Execution Checklist for Your New Workspace:
1. Initialize a clean Flutter project directory inside Android Studio.
2. Ensure your three models are placed in the project folder matching this layout:
   ```text
   placeholdernhai/assets/models/

```

3. Pass this `prompt.md` file to your AI assistant. It will generate a completely unique, cross-platform Dart-based ONNX implementation that satisfies your constraints, supports iOS, and installs safely without crashing on boot!