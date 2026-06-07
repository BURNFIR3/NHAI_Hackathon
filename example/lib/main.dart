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
              const SizedBox(height: 20),
              FutureBuilder<Map<String, String>>(
                future: storage.readAll(),
                builder: (context, snapshot) {
                  final count = snapshot.data?.length ?? 0;
                  return Text(
                    'DATABASE: $count PROFILES ENROLLED',
                    style: TextStyle(fontSize: 10, color: count > 0 ? Colors.greenAccent : Colors.white24, letterSpacing: 2),
                  );
                },
              ),
              const SizedBox(height: 40),
              if (!_engineReady)
                const CircularProgressIndicator(color: Colors.cyanAccent)
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
                const SizedBox(height: 40),
                TextButton.icon(
                  icon: const Icon(Icons.delete_sweep, color: Colors.redAccent, size: 18),
                  label: const Text('RESET SYSTEM DATA', style: TextStyle(color: Colors.redAccent, fontSize: 10, letterSpacing: 1.5)),
                  onPressed: () => _confirmReset(context),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _confirmReset(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.blueGrey.shade900,
        title: const Text('Reset All Data?', style: TextStyle(color: Colors.white)),
        content: const Text('This will permanently delete all registered facial profiles from this device.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              await storage.deleteAll();
              if (context.mounted) {
                Navigator.pop(context);
                Fluttertoast.showToast(msg: "All facial data deleted.");
              }
            },
            child: const Text('DELETE EVERYTHING', style: TextStyle(color: Colors.white)),
          ),
        ],
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
    // Use Medium for better compatibility with ImageAnalysis on some phones
    _controller = CameraController(front, ResolutionPreset.medium, enableAudio: false);
    await _controller!.initialize();
    if (!mounted) return;
    setState(() {});

    _controller!.startImageStream((image) => _processFrame(image));
  }

  Future<void> _processFrame(CameraImage image) async {
    if (_isProcessing || !_idEntered) return;

    final now = DateTime.now();
    if (_lastProcessTime != null && now.difference(_lastProcessTime!).inMilliseconds < 400) {
      return;
    }

    _isProcessing = true;
    _lastProcessTime = now;

    try {
      final detection = await widget.engine.detectFace(image);

      if (detection == null) {
        if (mounted) setState(() => _status = 'No face detected');
        _isProcessing = false;
        return;
      }

      if (mounted) setState(() => _status = 'Processing Face...');

      final img.Image converted = _convertCameraImage(image);
      final bbox = detection['bbox'] as List<double>;

      int px = bbox[0].toInt();
      int py = bbox[1].toInt();
      int pw = bbox[2].toInt();
      int ph = bbox[3].toInt();
      int padW = (pw * 0.15).toInt();
      int padH = (ph * 0.15).toInt();

      final faceCrop = img.copyCrop(
        converted,
        x: (px - padW).clamp(0, converted.width),
        y: (py - padH).clamp(0, converted.height),
        width: (pw + 2 * padW).clamp(1, converted.width - px),
        height: (ph + 2 * padH).clamp(1, converted.height - py),
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

    try {
      final directory = await getExternalStorageDirectory();
      if (directory != null) {
        final path = p.join(directory.path, 'registered_face_${_idController.text}.jpg');
        await File(path).writeAsBytes(img.encodeJpg(faceCrop));
        debugPrint('Registered face image saved to: $path');
      }
    } catch (e) {}

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
    final livenessScore = await widget.engine.checkLiveness(faceCrop);

    if (livenessScore < 0.6) {
      if (mounted) setState(() => _status = 'Liveness Check Failed');
      return;
    }

    if (mounted) setState(() => _status = 'Verifying Identity...');

    final liveEmbedding = await widget.engine.getEmbedding(faceCrop);
    if (liveEmbedding == null) return;

    final all = await widget.storage.readAll();
    if (all.isEmpty) {
      debugPrint('DATABASE EMPTY: No registered profiles found.');
      if (mounted) setState(() => _status = 'DATABASE EMPTY');
      return;
    }

    double highestSimilarity = -1.0;
    String? bestMatchId;

    debugPrint('--- IDENTITY SEARCH: COMPARING AGAINST ${all.length} USERS ---');
    for (var entry in all.entries) {
      try {
        final template = List<double>.from(jsonDecode(entry.value));
        final similarity = OnnxEngine.computeCosineSimilarity(liveEmbedding, template);
        debugPrint(' [CHECK] User: ${entry.key} | Similarity: ${similarity.toStringAsFixed(4)}');

        if (similarity > highestSimilarity) {
          highestSimilarity = similarity;
          bestMatchId = entry.key;
        }
      } catch (e) {
        debugPrint(' [ERROR] Could not parse profile for: ${entry.key}');
      }
    }

    if (bestMatchId != null && highestSimilarity > 0.65) {
      debugPrint(' >>> MATCH FOUND: $bestMatchId ($highestSimilarity)');
      HapticFeedback.heavyImpact();
      _finishFlow('Welcome, $bestMatchId');
    } else {
      debugPrint(' >>> NO MATCH (Best Score: $highestSimilarity)');
      if (mounted) {
        setState(() => _status = 'Mismatched (Best: ${highestSimilarity.toStringAsFixed(2)})');
      }
    }
  }

  void _finishFlow(String message, {bool success = true}) {
    if (_controller != null) {
      _controller?.stopImageStream();
      _controller?.dispose();
      if (mounted) {
        setState(() {
          _controller = null;
        });
      }
    }

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
