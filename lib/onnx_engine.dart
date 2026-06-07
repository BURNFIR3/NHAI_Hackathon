import 'dart:math' as math;
import 'dart:typed_data';
import 'package:onnxruntime_v2/onnxruntime_v2.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';

class OnnxEngine {
  OrtSession? _detectionSession;
  OrtSession? _recognitionSession;
  OrtSession? _livenessSession;

  final int _detWidth = 640;
  final int _detHeight = 640;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  Future<void> init() async {
    if (_isInitialized) return;

    debugPrint('[ONNX] Initializing ONNX Runtime Environment...');
    OrtEnv.instance.init();
    final sessionOptions = OrtSessionOptions();
    try {
      debugPrint('[ONNX] Appending Default Providers...');
      sessionOptions.appendDefaultProviders();
    } catch (e) {
      debugPrint('[ONNX] Hardware acceleration not available: $e');
    }

    debugPrint('[ONNX] Loading Face Detection Model (YuNet)...');
    _detectionSession = await _createSession('assets/models/face_detection_yunet_2023mar.onnx', sessionOptions);

    debugPrint('[ONNX] Loading Face Recognition Model (EdgeFace)...');
    _recognitionSession = await _createSession('assets/models/edgeface_xs_gamma_06.onnx', sessionOptions);

    debugPrint('[ONNX] Loading Liveness Model (MiniFASNet)...');
    _livenessSession = await _createSession('assets/models/best_model.onnx', sessionOptions);

    debugPrint('[ONNX] All models loaded successfully.');
    _isInitialized = true;
  }

  Future<OrtSession> _createSession(String assetPath, OrtSessionOptions options) async {
    final rawData = await rootBundle.load(assetPath);
    final bytes = rawData.buffer.asUint8List();
    return OrtSession.fromBuffer(bytes, options);
  }

  /// Highly optimized preprocessing from CameraImage to BGR Planar Float32List
  Float32List _preprocessYuNet(CameraImage image) {
    final Float32List bgrBuffer = Float32List(3 * _detHeight * _detWidth);

    final int uvRowStride = image.planes[1].bytesPerRow;
    final int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

    final int gOffset = _detHeight * _detWidth;
    final int bOffset = 2 * _detHeight * _detWidth;

    double scaleX = image.width / _detWidth;
    double scaleY = image.height / _detHeight;

    for (int y = 0; y < _detHeight; y++) {
      int srcY = (y * scaleY).toInt();
      int yRowOffset = srcY * image.planes[0].bytesPerRow;
      int uvRowOffset = (srcY >> 1) * uvRowStride;
      int destRowOffset = y * _detWidth;

      for (int x = 0; x < _detWidth; x++) {
        int srcX = (x * scaleX).toInt();
        int yIndex = yRowOffset + srcX;
        int uvIndex = uvRowOffset + (srcX >> 1) * uvPixelStride;

        int yp = image.planes[0].bytes[yIndex];
        int up = image.planes[1].bytes[uvIndex];
        int vp = image.planes[2].bytes[uvIndex];

        // YUV to RGB Integer conversion
        int r = (yp + 1.370705 * (vp - 128)).toInt().clamp(0, 255);
        int g = (yp - 0.337633 * (up - 128) - 0.698001 * (vp - 128)).toInt().clamp(0, 255);
        int b = (yp + 1.732446 * (up - 128)).toInt().clamp(0, 255);

        int destIndex = destRowOffset + x;
        // BGR Planar Layout for YuNet
        bgrBuffer[destIndex] = b.toDouble();
        bgrBuffer[gOffset + destIndex] = g.toDouble();
        bgrBuffer[bOffset + destIndex] = r.toDouble();
      }
    }
    return bgrBuffer;
  }

  // Detect face using YuNet
  Future<Map<String, dynamic>?> detectFace(CameraImage image) async {
    if (_detectionSession == null) return null;

    final inputData = _preprocessYuNet(image);
    final inputShape = [1, 3, _detHeight, _detWidth];
    final inputTensor = OrtValueTensor.createTensorWithDataList(inputData, inputShape);
    final inputs = {'input': inputTensor};

    try {
      final runOptions = OrtRunOptions();
      final outputs = await _detectionSession!.run(runOptions, inputs);

      if (outputs.isEmpty) return null;

      final outputValue = outputs[0]?.value as List;
      if (outputValue.isEmpty) {
        for (var o in outputs) { o?.release(); }
        return null;
      }

      // Handle YuNet output parsing logic [1, N, 15]
      List bestDetection;
      try {
        final firstLevel = outputValue[0] as List;
        if (firstLevel.isEmpty) {
           for (var o in outputs) { o?.release(); }
           return null;
        }
        if (firstLevel[0] is List) {
          bestDetection = firstLevel[0] as List;
        } else {
          bestDetection = firstLevel;
        }
      } catch (e) {
        for (var o in outputs) { o?.release(); }
        return null;
      }

      if (bestDetection.length < 15) {
        for (var o in outputs) { o?.release(); }
        return null;
      }

      final conf = (bestDetection[14] is double)
          ? bestDetection[14] as double
          : (bestDetection[14] as num).toDouble();

      debugPrint('YuNet Confidence: $conf');

      if (conf < 0.25) {
        for (var o in outputs) { o?.release(); }
        return null;
      }

      final result = {
        'bbox': [
          bestDetection[0] * image.width / _detWidth,
          bestDetection[1] * image.height / _detHeight,
          bestDetection[2] * image.width / _detWidth,
          bestDetection[3] * image.height / _detHeight,
        ],
        'conf': conf,
      };

      for (var o in outputs) { o?.release(); }
      return result;
    } finally {
      inputTensor.release();
    }
  }

  // Get Embedding using EdgeFace
  Future<List<double>?> getEmbedding(img.Image faceCrop) async {
    if (_recognitionSession == null) return null;

    final inputSize = 112;
    final resized = img.copyResize(faceCrop, width: inputSize, height: inputSize);

    final inputData = _imageToFloat32List(resized, [1, 3, inputSize, inputSize], normalize: true);
    final inputTensor = OrtValueTensor.createTensorWithDataList(inputData, [1, 3, inputSize, inputSize]);
    final inputs = {'input': inputTensor};

    try {
      final runOptions = OrtRunOptions();
      final outputs = await _recognitionSession!.run(runOptions, inputs);

      if (outputs.isEmpty) return null;
      final embeddingList = (outputs[0]?.value as List)[0] as List;
      final embedding = embeddingList.map((e) => e as double).toList();

      for (var o in outputs) { o?.release(); }
      return embedding;
    } finally {
      inputTensor.release();
    }
  }

  // Check Liveness using MiniFASNet
  Future<double> checkLiveness(img.Image faceCrop) async {
    if (_livenessSession == null) return 0.0;

    final inputSize = 80;
    final resized = img.copyResize(faceCrop, width: inputSize, height: inputSize, interpolation: img.Interpolation.nearest);

    final inputData = _imageToFloat32List(resized, [1, 3, inputSize, inputSize]);
    final inputTensor = OrtValueTensor.createTensorWithDataList(inputData, [1, 3, inputSize, inputSize]);
    final inputs = {'input': inputTensor};

    try {
      final runOptions = OrtRunOptions();
      final outputs = await _livenessSession!.run(runOptions, inputs);

      if (outputs.isEmpty) return 0.0;
      final scores = (outputs[0]?.value as List)[0] as List;
      final livenessScore = scores[1] as double;

      for (var o in outputs) { o?.release(); }
      return livenessScore;
    } finally {
      inputTensor.release();
    }
  }

  Float32List _imageToFloat32List(img.Image image, List<int> shape, {bool normalize = false, bool isBgr = false}) {
    final floatList = Float32List(shape[1] * shape[2] * shape[3]);
    var index = 0;

    // NCHW format
    for (var c = 0; c < 3; c++) {
      int channel = isBgr ? (2 - c) : c;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          final pixel = image.getPixel(x, y);
          double val;
          if (channel == 0) val = pixel.r.toDouble();
          else if (channel == 1) val = pixel.g.toDouble();
          else val = pixel.b.toDouble();

          if (normalize) {
            val = (val - 127.5) / 128.0;
          }
          floatList[index++] = val;
        }
      }
    }
    return floatList;
  }

  static double computeCosineSimilarity(List<double> v1, List<double> v2) {
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    for (int i = 0; i < v1.length; i++) {
      dotProduct += v1[i] * v2[i];
      normA += v1[i] * v1[i];
      normB += v2[i] * v2[i];
    }
    return dotProduct / (math.sqrt(normA) * math.sqrt(normB));
  }

  void dispose() {
    _detectionSession?.release();
    _recognitionSession?.release();
    _livenessSession?.release();
    OrtEnv.instance.release();
  }
}
