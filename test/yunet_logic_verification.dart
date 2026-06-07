import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:onnxruntime_v2/onnxruntime_v2.dart';

void main() {
  test('Verify YuNet Logic with Synthetic Data', () async {
    OrtEnv.instance.init();
    final sessionOptions = OrtSessionOptions();

    final modelPath = 'assets/models/face_detection_yunet_2023mar.onnx';
    final bytes = File(modelPath).readAsBytesSync();
    final session = OrtSession.fromBuffer(bytes, sessionOptions);

    print('Testing with Black Image...');
    final blackData = Float32List(1 * 3 * 640 * 640);
    // Fill with a specific value to see if it helps
    for(int i=0; i<blackData.length; i++) blackData[i] = 127.0;

    final blackTensor = OrtValueTensor.createTensorWithDataList(blackData, [1, 3, 640, 640]);
    final outputs = await session.run(OrtRunOptions(), {'input': blackTensor});

    for (int i = 0; i < outputs.length; i++) {
       final name = session.outputNames[i];
       final value = outputs[i]?.value as List;
       final level2 = value[0] as List;
       final level3 = level2[0] as List;

       double maxVal = -1000000.0;
       double minVal = 1000000.0;
       for (var row in level2) {
         for (var val in (row as List)) {
           if (val > maxVal) maxVal = val;
           if (val < minVal) minVal = val;
         }
       }

       print('Output $i ($name): shape=[1, ${level2.length}, ${level3.length}], min=$minVal, max=$maxVal');
    }

    for (var o in outputs) o?.release();
    blackTensor.release();
    session.release();
    OrtEnv.instance.release();
  });
}
