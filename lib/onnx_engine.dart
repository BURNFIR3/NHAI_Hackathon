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
    _detectionSession = await _createSession('assets/models/face_detection_yunet_2023mar.onnx', sessionOptions);
    _recognitionSession = await _createSession('assets/models/edgeface_xs_gamma_06.onnx', sessionOptions);
    _livenessSession = await _createSession('assets/models/best_model.onnx', sessionOptions);
    _isInitialized = true;
  }

  Future<OrtSession> _createSession(String assetPath, OrtSessionOptions options) async {
    final rawData = await rootBundle.load(assetPath);
    final bytes = rawData.buffer.asUint8List();
    return OrtSession.fromBuffer(bytes, options);
  }

  Float32List _preprocessForYuNet(CameraImage image) {
    final Float32List bgrBuffer = Float32List(3 * _detHeight * _detWidth);
    final int srcW = image.width;
    final int srcH = image.height;
    double scale = math.min(_detWidth / srcW, _detHeight / srcH);
    int newW = (srcW * scale).toInt();
    int newH = (srcH * scale).toInt();
    int offsetX = (_detWidth - newW) ~/ 2;
    int offsetY = (_detHeight - newH) ~/ 2;

    for (int y = 0; y < newH; y++) {
      int srcY = (y / scale).toInt().clamp(0, srcH - 1);
      int yRowOffset = srcY * image.planes[0].bytesPerRow;
      int uvRowOffset = (srcY >> 1) * image.planes[1].bytesPerRow;
      for (int x = 0; x < newW; x++) {
        int srcX = (x / scale).toInt().clamp(0, srcW - 1);
        int yp = image.planes[0].bytes[yRowOffset + srcX];
        int uvIdx = uvRowOffset + (srcX >> 1) * (image.planes[1].bytesPerPixel ?? 1);
        int up = image.planes[1].bytes[uvIdx];
        int vp = image.planes[2].bytes[uvIdx];

        int r = (yp + 1.3707 * (vp - 128)).toInt().clamp(0, 255);
        int g = (yp - 0.3376 * (up - 128) - 0.6980 * (vp - 128)).toInt().clamp(0, 255);
        int b = (yp + 1.7324 * (up - 128)).toInt().clamp(0, 255);

        int destIdx = (y + offsetY) * _detWidth + (x + offsetX);
        bgrBuffer[destIdx] = b.toDouble();
        bgrBuffer[_detWidth * _detHeight + destIdx] = g.toDouble();
        bgrBuffer[2 * _detWidth * _detHeight + destIdx] = r.toDouble();
      }
    }
    return bgrBuffer;
  }

  Future<Map<String, dynamic>?> detectFace(CameraImage image) async {
    if (_detectionSession == null) return null;
    final inputData = _preprocessForYuNet(image);
    final inputTensor = OrtValueTensor.createTensorWithDataList(inputData, [1, 3, _detHeight, _detWidth]);
    try {
      final outputs = await _detectionSession!.run(OrtRunOptions(), {'input': inputTensor});
      final List<_Candidate> candidates = [];
      final strides = [8, 16, 32];
      for (int i = 0; i < 3; i++) {
        final stride = strides[i];
        final List cls = (outputs[0 + i]?.value as List)[0];
        final List obj = (outputs[3 + i]?.value as List)[0];
        final List bbox = (outputs[6 + i]?.value as List)[0];
        final cols = _detWidth ~/ stride;
        for (int r = 0; r < (_detHeight ~/ stride); r++) {
          for (int c = 0; c < cols; c++) {
            int idx = r * cols + c;
            double score = (cls[idx][0] as num).toDouble() * (obj[idx][0] as num).toDouble();
            if (score > 0.3) {
               final box = bbox[idx] as List;
               candidates.add(_Candidate(rect: math.Rectangle((c + box[0]) * stride, (r + box[1]) * stride, math.exp(box[2]) * stride, math.exp(box[3]) * stride), score: score));
            }
          }
        }
      }
      for (var o in outputs) o?.release();
      if (candidates.isEmpty) return null;
      candidates.sort((a, b) => b.score.compareTo(a.score));
      final best = candidates.first;
      double scale = math.min(_detWidth / image.width, _detHeight / image.height);
      return {'bbox': [(best.rect.left - (_detWidth - image.width*scale)/2)/scale, (best.rect.top - (_detHeight - image.height*scale)/2)/scale, best.rect.width/scale, best.rect.height/scale], 'conf': best.score};
    } finally { inputTensor.release(); }
  }

  Future<List<double>?> getEmbedding(img.Image faceCrop) async {
    if (_recognitionSession == null) return null;

    // AGGRESSIVE ENHANCEMENT
    // 1. Boost Contrast and Brightness
    img.Image enhanced = img.adjustColor(faceCrop, contrast: 1.5, brightness: 1.1);
    // 2. Sharpening filter to reveal eye/nose details through blur
    enhanced = img.convolution(enhanced, filter: [0, -1, 0, -1, 5, -1, 0, -1, 0]);

    final resized = img.copyResize(enhanced, width: 112, height: 112);
    // EdgeFace uses RGB Planar, NOT BGR
    final inputData = _imageToFloat32List(resized, [1, 3, 112, 112], normalize: true, isBgr: false);
    final inputTensor = OrtValueTensor.createTensorWithDataList(inputData, [1, 3, 112, 112]);
    try {
      final outputs = await _recognitionSession!.run(OrtRunOptions(), {'input': inputTensor});
      final embedding = ((outputs[0]?.value as List)[0] as List).map((e) => (e as num).toDouble()).toList();
      for (var o in outputs) o?.release();
      return embedding;
    } finally { inputTensor.release(); }
  }

  Future<double> checkLiveness(img.Image faceCrop) async {
    if (_livenessSession == null) return 0.0;
    final resized = img.copyResize(faceCrop, width: 128, height: 128);
    final inputData = _imageToFloat32List(resized, [1, 3, 128, 128], normalize: true);
    final inputTensor = OrtValueTensor.createTensorWithDataList(inputData, [1, 3, 128, 128]);
    try {
      final outputs = await _livenessSession!.run(OrtRunOptions(), {'input': inputTensor});
      final List scores = (outputs[0]?.value as List)[0];
      for (var o in outputs) o?.release();
      double maxLogit = scores[0] > scores[1] ? scores[0] : scores[1];
      return math.exp(scores[1] - maxLogit) / (math.exp(scores[0] - maxLogit) + math.exp(scores[1] - maxLogit));
    } finally { inputTensor.release(); }
  }

  Float32List _imageToFloat32List(img.Image image, List<int> shape, {bool normalize = false, bool isBgr = false}) {
    final floatList = Float32List(shape[1] * shape[2] * shape[3]);
    var index = 0;
    for (var c = 0; c < 3; c++) {
      int channel = isBgr ? (2 - c) : c;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          final pixel = image.getPixel(x, y);
          double val = (channel == 0 ? pixel.r : (channel == 1 ? pixel.g : pixel.b)).toDouble();
          floatList[index++] = normalize ? (val - 127.5) / 128.0 : val;
        }
      }
    }
    return floatList;
  }

  static double computeCosineSimilarity(List<double> v1, List<double> v2) {
    double dotProduct = 0.0, normA = 0.0, normB = 0.0;
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

class _Candidate {
  final math.Rectangle rect;
  final double score;
  _Candidate({required this.rect, required this.score});
}
