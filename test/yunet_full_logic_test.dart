import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:onnxruntime_v2/onnxruntime_v2.dart';
import 'package:image/image.dart' as img;

void main() {
  test('Verify Full YuNet Decoding Logic', () async {
    OrtEnv.instance.init();
    final sessionOptions = OrtSessionOptions();

    final modelPath = 'assets/models/face_detection_yunet_2023mar.onnx';
    final session = OrtSession.fromBuffer(File(modelPath).readAsBytesSync(), sessionOptions);

    final imageBytes = File('test_face.jpg').readAsBytesSync();
    final image = img.decodeImage(imageBytes)!;
    final resized = img.copyResize(image, width: 640, height: 640);

    final bgrBuffer = Float32List(1 * 3 * 640 * 640);
    final int gOffset = 640 * 640;
    final int bOffset = 0; // The code in engine uses destIndex as B
    final int rOffset = 2 * 640 * 640;

    for (int y = 0; y < 640; y++) {
      for (int x = 0; x < 640; x++) {
        final pixel = resized.getPixel(x, y);
        final index = y * 640 + x;
        bgrBuffer[index] = pixel.b.toDouble();
        bgrBuffer[gOffset + index] = pixel.g.toDouble();
        bgrBuffer[rOffset + index] = pixel.r.toDouble();
      }
    }

    final inputTensor = OrtValueTensor.createTensorWithDataList(bgrBuffer, [1, 3, 640, 640]);
    final outputs = await session.run(OrtRunOptions(), {'input': inputTensor});

    final List<Detection> candidates = [];
    final strides = [8, 16, 32];

    for (int i = 0; i < 3; i++) {
      final stride = strides[i];
      final List cls = (outputs[0 + i]?.value as List)[0];
      final List obj = (outputs[3 + i]?.value as List)[0];
      final List bbox = (outputs[6 + i]?.value as List)[0];

      final cols = 640 ~/ stride;
      final rows = 640 ~/ stride;

      for (int r = 0; r < rows; r++) {
        for (int c = 0; c < cols; c++) {
          final idx = r * cols + c;
          final score = (cls[idx][0] as num).toDouble() * (obj[idx][0] as num).toDouble();

          if (score > 0.4) {
             final box = bbox[idx] as List;
             final cx = (c + (box[0] as num).toDouble()) * stride;
             final cy = (r + (box[1] as num).toDouble()) * stride;
             final w = math.exp((box[2] as num).toDouble()) * stride;
             final h = math.exp((box[3] as num).toDouble()) * stride;

             candidates.add(Detection(
               rect: math.Rectangle(cx - w/2, cy - h/2, w, h),
               score: score,
             ));
          }
        }
      }
    }

    print('Detected candidates: ${candidates.length}');
    for (var cand in candidates) {
      print('Candidate: rect=${cand.rect}, score=${cand.score}');
    }

    for (var o in outputs) o?.release();
    inputTensor.release();
    session.release();
    OrtEnv.instance.release();
  });
}

class Detection {
  final math.Rectangle rect;
  final double score;
  Detection({required this.rect, required this.score});
}
