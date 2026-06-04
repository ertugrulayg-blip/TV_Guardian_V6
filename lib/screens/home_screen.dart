// lib/screens/home_screen.dart
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../services/guardian_service.dart';
import '../services/tv_service.dart';
import '../services/voice_service.dart';
import '../services/distance_service.dart';
import 'pairing_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final cams = await availableCameras();
    await ref.read(distanceServiceProvider).initialize(cams);
    await ref.read(distanceServiceProvider).startDetection();
    await ref.read(voiceServiceProvider).initialize();
    await ref.read(voiceServiceProvider).startListening();
    ref.read(guardianServiceProvider).activate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    final d = ref.read(distanceServiceProvider);
    final g = ref.read(guardianServiceProvider);
    final v = ref.read(voiceServiceProvider);
    if (s == AppLifecycleState.paused) {
      d.stopDetection(); g.deactivate(); v.stopListening();
    } else if (s == AppLifecycleState.resumed) {
      d.startDetection(); g.activate(); v.startListening();
    }
  }

  @override
  Widget build(BuildContext context) {
    final guardian = ref.watch(guardianServiceProvider);
    final distance = ref.watch(distanceServiceProvider);
    final tv       = ref.watch(tvServiceProvider);
    final voice    = ref.watch(voiceServiceProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: SafeArea(
        child: Column(children: [
          // Top bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              const Text('TV Koruma 📺',
                  style: TextStyle(color: Colors.white,
                      fontSize: 17, fontWeight: FontWeight.w600)),
              const Spacer(),
              _chip(tv.isConnected ? 'TV Bağlı ✓' : 'TV Bağlı Değil',
                  tv.isConnected ? Colors.greenAccent : Colors.redAccent),
              const SizedBox(width: 8),
              _chip(voice.isListening ? '🎤 Dinliyor' : '🎤',
                  voice.isListening ? Colors.blueAccent : Colors.white24),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.link, color: Colors.white38, size: 20),
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const PairingScreen())),
              ),
            ]),
          ),

          // Uyarı banner
          if (guardian.state != GuardianState.idle)
            _Banner(state: guardian.state, countdown: guardian.countdownRemaining),

          const Spacer(),

          // Mesafe göstergesi
          _DistanceWidget(reading: distance.lastReading,
              threshold: guardian.warningDistanceCm),

          const Spacer(),

          // Aktif/pasif butonu
          GestureDetector(
            onTap: () => guardian.isActive
                ? guardian.deactivate()
                : guardian.activate(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              decoration: BoxDecoration(
                color: guardian.isActive
                    ? Colors.greenAccent.withOpacity(0.15)
                    : Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: guardian.isActive
                      ? Colors.greenAccent.withOpacity(0.5)
                      : Colors.white12,
                ),
              ),
              child: Text(
                guardian.isActive ? '⏸ Sistemi Durdur' : '▶ Sistemi Başlat',
                style: TextStyle(
                  color: guardian.isActive ? Colors.greenAccent : Colors.white54,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Hızlı kontroller
          if (tv.isConnected) _QuickControls(tv: tv),

          const SizedBox(height: 16),

          // Son olaylar
          if (guardian.events.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: guardian.events.take(3).map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Text(_icon(e.state), style: const TextStyle(fontSize: 12)),
                    const SizedBox(width: 6),
                    Expanded(child: Text(e.message,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11))),
                    Text('${e.time.hour}:${e.time.minute.toString().padLeft(2,'0')}',
                        style: const TextStyle(
                            color: Colors.white24, fontSize: 10)),
                  ]),
                )).toList(),
              ),
            ),

          const SizedBox(height: 16),
        ]),
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Text(label, style: TextStyle(color: color, fontSize: 11)),
  );

  String _icon(GuardianState s) => switch (s) {
    GuardianState.idle      => '✅',
    GuardianState.warning   => '⚠️',
    GuardianState.countdown => '⏳',
    GuardianState.tvOff     => '📴',
  };

  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); super.dispose(); }
}

// ─── Banner ───────────────────────────────────────────────────────────────────

class _Banner extends StatelessWidget {
  final GuardianState state;
  final int countdown;
  const _Banner({required this.state, required this.countdown});

  @override
  Widget build(BuildContext context) {
    final (String text, Color bg) = switch (state) {
      GuardianState.warning   => ('⚠️  Çok yakın! Lütfen geri gidin', Colors.orange.shade900),
      GuardianState.countdown => ('⏳  TV kapatılıyor... $countdown sn', Colors.red.shade900),
      GuardianState.tvOff     => ('📴  TV kapalı — güvenli mesafeye geçin', Colors.red.shade900),
      GuardianState.idle      => ('', Colors.transparent),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10),
      color: bg,
      child: Text(text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white,
              fontWeight: FontWeight.w600)),
    );
  }
}

// ─── Mesafe Göstergesi ────────────────────────────────────────────────────────

class _DistanceWidget extends StatelessWidget {
  final DistanceReading? reading;
  final double threshold;
  const _DistanceWidget({required this.reading, required this.threshold});

  @override
  Widget build(BuildContext context) {
    final dist = reading?.distanceCm;
    final detected = reading?.faceDetected ?? false;

    Color color = detected
        ? (dist! < threshold * 0.5 ? Colors.redAccent
           : dist < threshold ? Colors.orangeAccent
           : Colors.greenAccent)
        : Colors.white24;

    return Column(mainAxisSize: MainAxisSize.min, children: [
      Stack(alignment: Alignment.center, children: [
        SizedBox(
          width: 180, height: 180,
          child: CircularProgressIndicator(
            value: detected ? (1 - (dist! / (threshold * 2))).clamp(0.0, 1.0) : 0,
            strokeWidth: 8,
            backgroundColor: Colors.white.withOpacity(0.08),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            detected ? '${dist!.round()}' : '--',
            style: TextStyle(color: color, fontSize: 52,
                fontWeight: FontWeight.w700),
          ),
          Text(detected ? 'cm' : 'yüz yok',
              style: TextStyle(
                  color: color.withOpacity(0.6), fontSize: 14)),
        ]),
      ]),
      const SizedBox(height: 12),
      Text(
        detected
            ? (dist! < threshold ? '🚨 Çok yakın!' : '✅ Güvenli mesafe')
            : 'Kamera yüz arıyor...',
        style: TextStyle(color: color, fontSize: 14,
            fontWeight: FontWeight.w500),
      ),
    ]);
  }
}

// ─── Hızlı Kontroller ─────────────────────────────────────────────────────────

class _QuickControls extends StatelessWidget {
  final TvService tv;
  const _QuickControls({required this.tv});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _btn(Icons.power_settings_new, Colors.redAccent, tv.powerToggle),
        _btn(Icons.play_arrow, Colors.greenAccent, tv.play),
        _btn(Icons.pause, Colors.white70, tv.pause),
        _btn(Icons.volume_up, Colors.white70, tv.volumeUp),
        _btn(Icons.volume_down, Colors.white70, tv.volumeDown),
        _btn(Icons.home, Colors.blueAccent, tv.home),
      ]),
    );
  }

  Widget _btn(IconData icon, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 46, height: 46,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
      );
}
