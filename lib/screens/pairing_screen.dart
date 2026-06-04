// lib/screens/pairing_screen.dart
// Açılışta otomatik TV taraması yapar.
// Kullanıcı listeden TV'yi seçer → TV'de PIN çıkar → PIN'i girer → bitti.
// IP adresi yok, teknik bilgi yok.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../services/tv_service.dart';
import '../services/tv_discovery_service.dart';
import 'home_screen.dart';

class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});
  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  final _pinCtrl = TextEditingController();
  bool _loading = false;
  bool _waitingPin = false;       // PIN adımındayız
  String? _selectedIp;
  String? _selectedName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    // Daha önce eşleştirilen TV varsa direkt bağlan
    final tv = ref.read(tvServiceProvider);
    final savedIp = await tv.getSavedTvIp();
    if (savedIp != null && savedIp.isNotEmpty) {
      setState(() => _loading = true);
      final ok = await tv.connect(savedIp);
      if (ok && mounted) { _goHome(); return; }
      setState(() => _loading = false);
    }
    // Eşleştirilmiş TV yoksa veya bağlanamadıysa tara
    _scan();
  }

  Future<void> _scan() async {
    final discovery = ref.read(discoveryServiceProvider);
    await discovery.discover();
  }

  // Kullanıcı listeden bir TV'ye dokundu
  Future<void> _selectTv(DiscoveredTv tv) async {
    setState(() { _loading = true; _selectedIp = tv.ip; _selectedName = tv.name; });
    final tvService = ref.read(tvServiceProvider);
    final ok = await tvService.startPairing(tv.ip);
    setState(() => _loading = false);

    if (ok) {
      setState(() => _waitingPin = true);
    } else {
      _showError(tvService.errorMessage ?? 'Bağlanamadı');
    }
  }

  Future<void> _confirmPin() async {
    final pin = _pinCtrl.text.trim();
    if (pin.length < 4) return;

    setState(() => _loading = true);
    final tvService = ref.read(tvServiceProvider);
    final ok = await tvService.confirmPin(pin);
    setState(() => _loading = false);

    if (ok) {
      _goHome();
    } else {
      _showError('Yanlış PIN. TV ekranındaki kodu kontrol et.');
      _pinCtrl.clear();
    }
  }

  void _goHome() => Navigator.pushReplacement(
      context, MaterialPageRoute(builder: (_) => const HomeScreen()));

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent));

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
              const Text('📺', style: TextStyle(fontSize: 44)),
              const SizedBox(height: 12),
              const Text('TV Koruma',
                  style: TextStyle(color: Colors.white, fontSize: 26,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                _waitingPin
                    ? '"$_selectedName" TV ekranındaki PIN\'i girin'
                    : 'Ağınızdaki televizyonlar aranıyor...',
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),

              const SizedBox(height: 32),

              if (_loading)
                const Center(child: CircularProgressIndicator())
              else if (_waitingPin)
                _buildPinStep()
              else
                _buildTvList(discovery),
            ],
          ),
        ),
      ),
    );
  }

  // ─── TV Listesi ───────────────────────────────────────────────────────────

  Widget _buildTvList(TvDiscoveryService discovery) {
    return Expanded(
      child: Column(
        children: [
          // Durum satırı
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
            _buildNotFound()
          else
            Expanded(
              child: ListView.builder(
                itemCount: discovery.foundTvs.length,
                itemBuilder: (_, i) => _TvCard(
                  tv: discovery.foundTvs[i],
                  onTap: () => _selectTv(discovery.foundTvs[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNotFound() {
    return Expanded(
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('📺', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          const Text('TV bulunamadı',
              style: TextStyle(color: Colors.white54, fontSize: 16)),
          const SizedBox(height: 8),
          const Text(
            'TV ve telefon aynı WiFi ağında\nolduğundan emin olun',
            style: TextStyle(color: Colors.white24, fontSize: 13, height: 1.5),
            textAlign: TextAlign.center,
          ),
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
      ),
    );
  }

  // ─── PIN Adımı ────────────────────────────────────────────────────────────

  Widget _buildPinStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Görsel açıklama
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
          ),
          child: Row(children: [
            const Text('📺', style: TextStyle(fontSize: 36)),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'TV ekranına bakın — 6 haneli bir kod\ngörünüyor olmalı',
                style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
              ),
            ),
          ]),
        ),

        const SizedBox(height: 24),

        const Text('TV\'deki PIN',
            style: TextStyle(color: Colors.white54, fontSize: 13)),
        const SizedBox(height: 8),

        TextField(
          controller: _pinCtrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          style: const TextStyle(color: Colors.white, fontSize: 28,
              letterSpacing: 10, fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            hintText: '------',
            hintStyle: const TextStyle(color: Colors.white12, letterSpacing: 10),
            filled: true,
            fillColor: Colors.white.withOpacity(0.08),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
            counterStyle: const TextStyle(color: Colors.white24),
          ),
          onSubmitted: (_) => _confirmPin(),
        ),

        const SizedBox(height: 16),

        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _confirmPin,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.greenAccent.shade700,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Onayla',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ),

        const SizedBox(height: 12),
        TextButton(
          onPressed: () => setState(() { _waitingPin = false; _pinCtrl.clear(); }),
          child: const Text('← Geri dön',
              style: TextStyle(color: Colors.white38)),
        ),
      ],
    );
  }
}

// ─── TV Kartı ─────────────────────────────────────────────────────────────────

class _TvCard extends StatelessWidget {
  final DiscoveredTv tv;
  final VoidCallback onTap;
  const _TvCard({required this.tv, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
            child: const Icon(Icons.tv, color: Colors.blueAccent, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tv.name,
                  style: const TextStyle(color: Colors.white,
                      fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(tv.ip,
                  style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          )),
          const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 14),
        ]),
      ),
    );
  }
}
