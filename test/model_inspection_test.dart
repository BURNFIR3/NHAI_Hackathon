import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:onnxruntime_v2/onnxruntime_v2.dart';

void main() {
  test('Inspect All Models', () async {
    OrtEnv.instance.init();
    final sessionOptions = OrtSessionOptions();

    for (var modelName in ['face_detection_yunet_2023mar.onnx', 'edgeface_xs_gamma_06.onnx', 'best_model.onnx']) {
      final modelPath = 'assets/models/$modelName';
      final modelFile = File(modelPath);

      if (!modelFile.existsSync()) {
        print('Model $modelName not found at $modelPath');
        continue;
      }

      final bytes = modelFile.readAsBytesSync();
      final session = OrtSession.fromBuffer(bytes, sessionOptions);

      print('\n--- $modelName Info ---');
      print('Inputs:');
      for (var input in session.inputNames) {
        print('  - $input');
      }
      print('Outputs:');
      for (var output in session.outputNames) {
        print('  - $output');
      }

      session.release();
    }

    OrtEnv.instance.release();
  });
}
