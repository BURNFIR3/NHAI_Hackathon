import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:onnxruntime_v2/onnxruntime_v2.dart';
import 'package:image/image.dart' as img;

void main() {
  test('PC EdgeFace Robustness Test', () async {
    OrtEnv.instance.init();
    final sessionOptions = OrtSessionOptions();

    final recPath = 'assets/models/edgeface_xs_gamma_06.onnx';
    final recSession = OrtSession.fromBuffer(File(recPath).readAsBytesSync(), sessionOptions);

    // Load the image you just pulled from the phone
    final imageBytes = File('huzefa_face.jpg').readAsBytesSync();
    final image = img.decodeImage(imageBytes)!;

    // Preprocess exactly like the app does
    final resized = img.copyResize(image, width: 112, height: 112);
    final inputData = Float32List(1 * 3 * 112 * 112);
    var index = 0;

    // RGB Normalization
    for (var c = 0; c < 3; c++) {
      for (var y = 0; y < 112; y++) {
        for (var x = 0; x < 112; x++) {
          final pixel = resized.getPixel(x, y);
          double val = (c == 0 ? pixel.r : (c == 1 ? pixel.g : pixel.b)).toDouble();
          inputData[index++] = (val - 127.5) / 128.0;
        }
      }
    }

    final inputTensor = OrtValueTensor.createTensorWithDataList(inputData, [1, 3, 112, 112]);
    final outputs = await recSession.run(OrtRunOptions(), {'input': inputTensor});

    final embedding = (outputs[0]?.value as List)[0] as List;
    print('\n--- EdgeFace Results for huzefa_face.jpg ---');
    print('Embedding Length: ${embedding.length}');

    // Check for "Dead" embedding (all zeros or NaNs)
    double sum = 0;
    for (var val in embedding) sum += (val as double).abs();
    print('Embedding Magnitude (Sum of Abs): $sum');

    if (sum > 1.0) {
      print('SUCCESS: The model successfully extracted features even from the blurry image.');
    } else {
      print('FAILURE: The image is too blurry; the model produced an empty feature set.');
    }

    for(var o in outputs) o?.release();
    inputTensor.release();
    recSession.release();
    OrtEnv.instance.release();
  });
}
