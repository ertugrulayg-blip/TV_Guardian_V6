// lib/services/distance_service.dart
import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Size;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class DistanceReading {
  final double? distanceCm;
  final int faceCount;
  final DateTime timestamp;

  const DistanceReading({
    required this.distanceCm,
    required this.faceCount,
    required this.timestamp,
  });

  bool get faceDetected => distanceCm != null;
  bool isTooClose(double threshold) => faceDetected && distanceCm! < threshold;
}

class DistanceService extends ChangeNotifier {
  static const double _realFaceWidthMm = 140.0;
  double _focalLength = 600.0;

  CameraController? _camera;
  FaceDetector? _detector;
  bool _isRunning = false;
  DistanceReading? _lastReading;
  Timer? _throttle;
  bool _processing = false;
  final List<double> _buf = [];

  DistanceReading? get lastReading => _lastReading;
  bool get isRunning => _isRunning;

  final _stream = StreamController<DistanceReading>.broadcast();
  Stream<DistanceReading> get distanceStream => _stream.stream;

  Future<void> initialize(List<CameraDescription> cameras) async {
    final cam = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    _camera = CameraController(cam, ResolutionPreset.medium,
        enableAudio: false, imageFormatGroup: ImageFormatGroup.nv21);
    await _camera!.initialize();

    _detector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        minFaceSize: 0.1,
      ),
    );
  }

  Future<void> startDetection() async {
    if (_camera == null || _isRunning) return;
    _isRunning = true;
    _camera!.startImageStream((img) {
      if (_processing || _throttle != null) return;
      _throttle = Timer(const Duration(milliseconds: 250), () => _throttle = null);
      _processFrame(img);
    });
    notifyListeners();
  }

  Future<void> stopDetection() async {
    _isRunning = false;
    await _camera?.stopImageStream();
    _buf.clear();
    notifyListeners();
  }

  Future<void> _processFrame(CameraImage img) async {
    if (_processing || _detector == null) return;
    _processing = true;
    try {
      final input = _toInputImage(img);
      if (input == null) return;

      final faces = await _detector!.processImage(input);
      if (faces.isEmpty) { _emit(null, 0); return; }

      final biggest = faces.reduce(
          (a, b) => a.boundingBox.width > b.boundingBox.width ? a : b);
      final px = biggest.boundingBox.width;
      if (px <= 0) return;

      final raw = (_realFaceWidthMm * _focalLength) / px / 10;
      _buf.add(raw);
      if (_buf.length > 5) _buf.removeAt(0);
      final avg = _buf.reduce((a, b) => a + b) / _buf.length;
      _emit(avg, faces.length);
    } catch (e) {
      debugPrint('Frame hata: $e');
    } finally {
      _processing = false;
    }
  }

  void _emit(double? cm, int count) {
    final r = DistanceReading(
        distanceCm: cm, faceCount: count, timestamp: DateTime.now());
    _lastReading = r;
    _stream.add(r);
    notifyListeners();
  }

  void calibrate(double knownCm, double pixelWidth) {
    if (pixelWidth <= 0 || knownCm <= 0) return;
    _focalLength = (pixelWidth * knownCm * 10) / _realFaceWidthMm;
    debugPrint('Kalibrasyon: odak=$_focalLength');
  }

  InputImage? _toInputImage(CameraImage img) {
    try {
      final rot = _rotation(_camera!.description.sensorOrientation);
      if (rot == null) return null;
      final fmt = InputImageFormatValue.fromRawValue(img.format.raw);
      if (fmt == null) return null;
      final p = img.planes.first;
      return InputImage.fromBytes(
        bytes: p.bytes,
        metadata: InputImageMetadata(
          size: Size(img.width.toDouble(), img.height.toDouble()),
          rotation: rot,
          format: fmt,
          bytesPerRow: p.bytesPerRow,
        ),
      );
    } catch (_) { return null; }
  }

  InputImageRotation? _rotation(int deg) => switch (deg) {
    0 => InputImageRotation.rotation0deg,
    90 => InputImageRotation.rotation90deg,
    180 => InputImageRotation.rotation180deg,
    270 => InputImageRotation.rotation270deg,
    _ => null,
  };

  @override
  void dispose() {
    stopDetection();
    _camera?.dispose();
    _detector?.close();
    _stream.close();
    _throttle?.cancel();
    super.dispose();
  }
}
