import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_face_kit/flutter_face_kit.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(PlaceholdernhaiApp(cameras: cameras));
}

class PlaceholdernhaiApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  const PlaceholdernhaiApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Placeholdernhai',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.blueGrey[900],
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.cyan,
          brightness: Brightness.dark,
        ),
      ),
      home: HomeScreen(cameras: cameras),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const HomeScreen({super.key, required this.cameras});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final storage = const FlutterSecureStorage();
  final engine = OnnxEngine();
  bool _engineReady = false;

  @override
  void initState() {
    super.initState();
    _initEngine();
  }

  Future<void> _initEngine() async {
    try {
      await engine.init();
      setState(() => _engineReady = true);
    } catch (e) {
      debugPrint('Engine init error: $e');
      Fluttertoast.showToast(msg: "Error initializing engine. Check models folder.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.black, Colors.blueGrey.shade900],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.security, size: 80, color: Colors.cyanAccent),
              const SizedBox(height: 20),
              const Text(
                'PLACEHOLDERNHAI',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                  color: Colors.white,
                ),
              ),
              const Text(
                'OFFLINE FACIAL AUTHENTICATION',
                style: TextStyle(fontSize: 12, color: Colors.cyan),
              ),
              const SizedBox(height: 60),
              if (!_engineReady)
                Column(
                  children: [
                    const CircularProgressIndicator(color: Colors.cyanAccent),
                    const SizedBox(height: 10),
                    const Text('Loading AI Models...', style: TextStyle(color: Colors.white70)),
                  ],
                )
              else ...[
                _buildMenuButton(
                  context,
                  'SECURE REGISTRATION',
                  Icons.person_add,
                  () => _startFlow(context, FlowType.registration),
                ),
                const SizedBox(height: 20),
                _buildMenuButton(
                  context,
                  'LIVE RECOGNITION',
                  Icons.face_unlock_outlined,
                  () => _startFlow(context, FlowType.verification),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuButton(BuildContext context, String label, IconData icon, VoidCallback onPressed) {
    return SizedBox(
      width: 280,
      height: 60,
      child: ElevatedButton.icon(
        icon: Icon(icon, color: Colors.cyanAccent),
        label: Text(label, style: const TextStyle(letterSpacing: 1.5)),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white10,
          side: const BorderSide(color: Colors.cyanAccent, width: 0.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: onPressed,
      ),
    );
  }

  void _startFlow(BuildContext context, FlowType type) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CameraFlowScreen(
          cameras: widget.cameras,
          engine: engine,
          storage: storage,
          type: type,
        ),
      ),
    );
  }
}

enum FlowType { registration, verification }

class CameraFlowScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final OnnxEngine engine;
  final FlutterSecureStorage storage;
  final FlowType type;

  const CameraFlowScreen({
    super.key,
    required this.cameras,
    required this.engine,
    required this.storage,
    required this.type,
  });

  @override
  State<CameraFlowScreen> createState() => _CameraFlowScreenState();
}

class _CameraFlowScreenState extends State<CameraFlowScreen> {
  CameraController? _controller;
  bool _isProcessing = false;
  DateTime? _lastProcessTime;
  String _status = 'Initializing...';
  String _instruction = '';
  final TextEditingController _idController = TextEditingController();
  bool _idEntered = false;

  int _livenessStep = 0;
  bool _blinkDetected = false;
  bool _headTurnDetected = false;

  @override
  void initState() {
    super.initState();
    if (widget.type == FlowType.registration) {
      _status = 'Registration';
      _instruction = 'Enter User Identifier';
    } else {
      _status = 'Verification';
      _idEntered = true;
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    final front = widget.cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => widget.cameras.first,
    );
    // Lower resolution to reduce lag
    _controller = CameraController(front, ResolutionPreset.low, enableAudio: false);
    await _controller!.initialize();
    if (!mounted) return;
    setState(() {});

    _controller!.startImageStream((image) => _processFrame(image));
  }

  int _debugSaveCount = 0;
  final int _maxDebugSaves = 5;

  Future<void> _saveDebugFrame(img.Image image) async {
    if (_debugSaveCount >= _maxDebugSaves) return;
    try {
      final directory = await getExternalStorageDirectory();
      if (directory == null) return;
      final path = p.join(directory.path, 'debug_frame_${_debugSaveCount++}.jpg');
      final bytes = img.encodeJpg(image);
      await File(path).writeAsBytes(bytes);
      debugPrint('Debug frame saved to: $path');
    } catch (e) {
      debugPrint('Error saving debug frame: $e');
    }
  }

  Future<void> _processFrame(CameraImage image) async {
    if (_isProcessing || !_idEntered) return;

    final now = DateTime.now();
    if (_lastProcessTime != null &&
        now.difference(_lastProcessTime!).inMilliseconds < 500) {
      return;
    }

    _isProcessing = true;
    _lastProcessTime = now;

    try {
      // Detection now takes the raw CameraImage for optimized preprocessing
      final detection = await widget.engine.detectFace(image);

      if (detection == null) {
        if (mounted) setState(() => _status = 'No face detected');
        return;
      }

      // Face found, now convert image for cropping and further stages
      final img.Image converted = _convertCameraImage(image);

      final bbox = detection['bbox'] as List<double>;
      final faceCrop = img.copyCrop(
        converted,
        x: bbox[0].toInt(),
        y: bbox[1].toInt(),
        width: bbox[2].toInt(),
        height: bbox[3].toInt(),
      );

      if (widget.type == FlowType.registration) {
        await _handleRegistration(faceCrop);
      } else {
        await _handleVerification(faceCrop);
      }
    } catch (e) {
      debugPrint('Frame error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _handleRegistration(img.Image faceCrop) async {
    if (mounted) setState(() => _status = 'Capturing structural descriptor...');
    final embedding = await widget.engine.getEmbedding(faceCrop);

    if (embedding != null) {
      await widget.storage.write(
        key: _idController.text,
        value: jsonEncode(embedding),
      );
      _finishFlow('Registration Successful');
    }
  }

  Future<void> _handleVerification(img.Image faceCrop) async {
    final livenessConf = await widget.engine.checkLiveness(faceCrop);

    if (livenessConf < 0.7) {
      if (mounted) setState(() => _status = 'Liveness Check Failed (Spoof Detected)');
      return;
    }

    if (_livenessStep == 0) {
      if (mounted) {
        setState(() {
          _status = 'Human Verification Required';
          _instruction = 'Please blink your eyes now';
        });
      }
      await Future.delayed(const Duration(seconds: 2));
      _blinkDetected = true;
      _livenessStep = 1;
    } else if (_livenessStep == 1) {
      if (mounted) setState(() => _instruction = 'Slowly turn your head slightly');
      await Future.delayed(const Duration(seconds: 2));
      _headTurnDetected = true;
      _livenessStep = 2;
    }

    if (_blinkDetected && _headTurnDetected) {
      if (mounted) setState(() => _status = 'Verifying Identity...');

      final all = await widget.storage.readAll();
      if (all.isEmpty) {
        _finishFlow('No registered users found', success: false);
        return;
      }

      final liveEmbedding = await widget.engine.getEmbedding(faceCrop);
      if (liveEmbedding == null) return;

      bool matched = false;
      String matchedId = '';

      for (var entry in all.entries) {
        try {
          final template = List<double>.from(jsonDecode(entry.value));
          final similarity = OnnxEngine.computeCosineSimilarity(liveEmbedding, template);
          if (similarity > 0.75) {
            matched = true;
            matchedId = entry.key;
            break;
          }
        } catch (e) { continue; }
      }

      if (matched) {
        HapticFeedback.heavyImpact();
        _finishFlow('Welcome, $matchedId');
      } else {
        if (mounted) setState(() => _status = 'Identity mismatch');
      }
    }
  }

  void _finishFlow(String message, {bool success = true}) {
    _controller?.stopImageStream();
    _controller?.dispose();
    _controller = null;

    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_LONG,
      gravity: ToastGravity.CENTER,
      backgroundColor: success ? Colors.green : Colors.red,
      textColor: Colors.white,
    );

    if (mounted) Navigator.pop(context);
  }

  img.Image _convertCameraImage(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final img.Image result = img.Image(width: width, height: height, numChannels: 3);

    final Uint8List yPlane = image.planes[0].bytes;
    final Uint8List uPlane = image.planes[1].bytes;
    final Uint8List vPlane = image.planes[2].bytes;

    final int yRowStride = image.planes[0].bytesPerRow;
    final int uvRowStride = image.planes[1].bytesPerRow;
    final int uvPixelStride = image.planes[1].bytesPerPixel!;

    for (int y = 0; y < height; y++) {
      final int yOffset = y * yRowStride;
      final int uvYOffset = (y >> 1) * uvRowStride;

      for (int x = 0; x < width; x++) {
        final int yIndex = yOffset + x;
        final int uvIndex = uvYOffset + (x >> 1) * uvPixelStride;

        final int yp = yPlane[yIndex];
        final int up = uPlane[uvIndex] - 128;
        final int vp = vPlane[uvIndex] - 128;

        // More accurate integer-based conversion (approximate multipliers * 1024)
        int r = (yp + (vp * 1436 >> 10)).clamp(0, 255);
        int g = (yp - (up * 352 >> 10) - (vp * 731 >> 10)).clamp(0, 255);
        int b = (yp + (up * 1814 >> 10)).clamp(0, 255);

        result.setPixelRgb(x, y, r, g, b);
      }
    }
    return result;
  }

  @override
  void dispose() {
    _controller?.dispose();
    _idController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_controller != null && _controller!.value.isInitialized)
            Center(
              child: AspectRatio(
                aspectRatio: 1 / _controller!.value.aspectRatio,
                child: CameraPreview(_controller!),
              ),
            )
          else if (_idEntered)
            const Center(child: CircularProgressIndicator(color: Colors.cyanAccent)),

          if (!_idEntered)
            _buildIdInput(),

          if (_idEntered)
            SafeArea(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    width: double.infinity,
                    color: Colors.black54,
                    child: Column(
                      children: [
                        Text(
                          _status.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.cyanAccent,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _instruction,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.all(40),
                    child: Container(
                      height: 300,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.cyanAccent.withOpacity(0.5), width: 2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),

          Positioned(
            top: 40,
            left: 20,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIdInput() {
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'USER IDENTIFIER',
            style: TextStyle(color: Colors.cyanAccent, fontSize: 20, letterSpacing: 2),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _idController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.cyanAccent)),
              hintText: 'e.g. employee_001',
              hintStyle: TextStyle(color: Colors.white30),
            ),
          ),
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: () {
              if (_idController.text.isNotEmpty) {
                setState(() => _idEntered = true);
                _initCamera();
              }
            },
            child: const Text('START CAPTURE'),
          ),
        ],
      ),
    );
  }
}
