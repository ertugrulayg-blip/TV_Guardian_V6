// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'screens/pairing_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const ProviderScope(child: App()));
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'TV Koruma',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4A90E2), brightness: Brightness.dark),
      useMaterial3: true,
    ),
    home: const _PermissionGate(),
  );
}

class _PermissionGate extends StatefulWidget {
  const _PermissionGate();
  @override
  State<_PermissionGate> createState() => _PermGateState();
}

class _PermGateState extends State<_PermissionGate> {
  bool _checked = false;
  bool _granted = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final r = await [Permission.camera, Permission.microphone].request();
    setState(() {
      _checked = true;
      _granted = r.values.every((s) => s.isGranted);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) return const Scaffold(
      backgroundColor: Color(0xFF0D0D1A),
      body: Center(child: CircularProgressIndicator()),
    );

    if (!_granted) return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('📷', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 16),
          const Text('Kamera ve Mikrofon İzni',
              style: TextStyle(color: Colors.white, fontSize: 20,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text(
            'Mesafe ölçümü için kamera,\nsesli komutlar için mikrofon gerekli.',
            style: TextStyle(color: Colors.white54, height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => openAppSettings(),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            child: const Text('Ayarları Aç'),
          ),
        ]),
      )),
    );

    return const PairingScreen();
  }
}
