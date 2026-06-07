import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:onnxruntime_v2/onnxruntime_v2.dart';
import 'package:image/image.dart' as img;

void main() {
  test('Verify Recognition and Liveness Models', () async {
    OrtEnv.instance.init();
    final sessionOptions = OrtSessionOptions();

    // Recognition Test
    print('Testing EdgeFace...');
    final recPath = 'assets/models/edgeface_xs_gamma_06.onnx';
    final recSession = OrtSession.fromBuffer(File(recPath).readAsBytesSync(), sessionOptions);

    final recData = Float32List(1 * 3 * 112 * 112);
    final recTensor = OrtValueTensor.createTensorWithDataList(recData, [1, 3, 112, 112]);
    final recOutputs = await recSession.run(OrtRunOptions(), {'input': recTensor});

    final embedding = (recOutputs[0]?.value as List)[0] as List;
    print('Embedding length: ${embedding.length}');

    for(var o in recOutputs) o?.release();
    recTensor.release();
    recSession.release();

    // Liveness Test
    print('\nTesting MiniFASNet...');
    final livePath = 'assets/models/best_model.onnx';
    final liveSession = OrtSession.fromBuffer(File(livePath).readAsBytesSync(), sessionOptions);

    final liveData = Float32List(1 * 3 * 80 * 80);
    final liveTensor = OrtValueTensor.createTensorWithDataList(liveData, [1, 3, 80, 80]);
    final liveOutputs = await liveSession.run(OrtRunOptions(), {'input': liveTensor});

    final scores = (liveOutputs[0]?.value as List)[0] as List;
    print('Liveness scores: $scores');

    for(var o in liveOutputs) o?.release();
    liveTensor.release();
    liveSession.release();

    OrtEnv.instance.release();
  });
}
