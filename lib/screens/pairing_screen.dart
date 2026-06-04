// lib/screens/pairing_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../services/tv_discovery_service.dart';
import 'home_screen.dart';

class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});
  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    // Daha once baglanilan TV varsa direkt baglan
    final tv = ref.read(tvServiceProvider);
    final savedIp = await tv.getSavedTvIp();
    if (savedIp != null && savedIp.isNotEmpty) {
      setState(() => _loading = true);
      final ok = await tv.connect(savedIp);
      if (ok && mounted) { _goHome(); return; }
      setState(() => _loading = false);
    }
    // Agdaki TV leri tara
    _scan();
  }

  Future<void> _scan() async {
    await ref.read(discoveryServiceProvider).discover();
  }

  Future<void> _selectTv(DiscoveredTv tv) async {
    setState(() => _loading = true);
    final tvService = ref.read(tvServiceProvider);
    final ok = await tvService.connect(tv.ip, port: tv.port);
    setState(() => _loading = false);

    if (ok && mounted) {
      _goHome();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tvService.errorMessage ?? 'Baglanamadi'),
          backgroundColor: Colors.redAccent,
        ));
      }
    }
  }

  void _goHome() => Navigator.pushReplacement(
      context, MaterialPageRoute(builder: (_) => const HomeScreen()));

  @override
  Widget build(BuildContext context) {
    final discovery = ref.watch(discoveryServiceProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              const Text('TV Koruma',
                  style: TextStyle(color: Colors.white, fontSize: 26,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text('Aginizdaki televizyonlar aranıyor...',
                  style: TextStyle(color: Colors.white54, fontSize: 14)),
              const SizedBox(height: 32),

              if (_loading)
                const Center(child: CircularProgressIndicator())
              else
                Expanded(child: _buildTvList(discovery)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTvList(TvDiscoveryService discovery) {
    return Column(
      children: [
        Row(children: [
          if (discovery.isScanning) ...[
            const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2,
                    color: Colors.blueAccent)),
            const SizedBox(width: 10),
          ],
          Expanded(child: Text(discovery.scanStatus,
              style: const TextStyle(color: Colors.white38, fontSize: 12))),
          if (!discovery.isScanning)
            TextButton.icon(
              onPressed: _scan,
              icon: const Icon(Icons.refresh, size: 16, color: Colors.blueAccent),
              label: const Text('Tekrar Tara',
                  style: TextStyle(color: Colors.blueAccent, fontSize: 12)),
            ),
        ]),
        const SizedBox(height: 12),
        if (discovery.foundTvs.isEmpty && !discovery.isScanning)
          Expanded(child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('TV bulunamadi',
                  style: TextStyle(color: Colors.white54, fontSize: 16)),
              const SizedBox(height: 8),
              const Text('TV ve telefon ayni WiFi aginda olmali',
                  style: TextStyle(color: Colors.white24, fontSize: 13)),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _scan,
                icon: const Icon(Icons.refresh, color: Colors.white54),
                label: const Text('Tekrar Ara',
                    style: TextStyle(color: Colors.white54)),
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24)),
              ),
            ]),
          ))
        else
          Expanded(
            child: ListView.builder(
              itemCount: discovery.foundTvs.length,
              itemBuilder: (_, i) {
                final tv = discovery.foundTvs[i];
                return GestureDetector(
                  onTap: () => _selectTv(tv),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Row(children: [
                      Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.tv, color: Colors.blueAccent),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tv.name, style: const TextStyle(
                              color: Colors.white, fontSize: 15,
                              fontWeight: FontWeight.w600)),
                          Text(tv.ip, style: const TextStyle(
                              color: Colors.white38, fontSize: 12)),
                        ],
                      )),
                      const Icon(Icons.arrow_forward_ios,
                          color: Colors.white24, size: 14),
                    ]),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
