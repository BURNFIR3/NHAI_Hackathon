import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:onnxruntime_v2/onnxruntime_v2.dart';
import 'package:image/image.dart' as img;

void main() {
  test('Verify YuNet with Real Face Image', () async {
    OrtEnv.instance.init();
    final sessionOptions = OrtSessionOptions();

    final modelPath = 'assets/models/face_detection_yunet_2023mar.onnx';
    final session = OrtSession.fromBuffer(File(modelPath).readAsBytesSync(), sessionOptions);

    final imageBytes = File('test_face.jpg').readAsBytesSync();
    final image = img.decodeImage(imageBytes)!;
    final resized = img.copyResize(image, width: 640, height: 640);

    final bgrBuffer = Float32List(1 * 3 * 640 * 640);
    final int gOffset = 640 * 640;
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

    // Check objectness scores (stride 8, 16, 32 are indices 3, 4, 5)
    for (int i = 3; i <= 5; i++) {
       final name = session.outputNames[i];
       final value = outputs[i]?.value as List;
       final level2 = value[0] as List;

       double maxVal = -1.0;
       for (var row in level2) {
         double val = (row as List)[0];
         if (val > maxVal) maxVal = val;
       }
       print('Stride level $i ($name): max objectness = $maxVal');
    }

    for (var o in outputs) o?.release();
    inputTensor.release();
    session.release();
    OrtEnv.instance.release();
  });
}
