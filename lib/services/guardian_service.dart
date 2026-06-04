// lib/services/guardian_service.dart
// Mesafe okumalarını takip eder, durum makinesini yönetir.
// Çok yakın → sesli uyarı → 10sn geri sayım → TV kapat → geri dönünce aç

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'tv_service.dart';
import 'distance_service.dart';

enum GuardianState { idle, warning, countdown, tvOff }

class GuardianEvent {
  final DateTime time;
  final String message;
  final GuardianState state;
  GuardianEvent(this.message, this.state) : time = DateTime.now();
}

class GuardianService extends ChangeNotifier {
  final TvService _tv;
  final DistanceService _distance;
  late final FlutterTts _tts;

  // Ayarlar
  double warningDistanceCm = 150.0;
  double safeDistanceCm = 170.0;
  int countdownSeconds = 10;

  // Durum
  GuardianState _state = GuardianState.idle;
  bool _isActive = false;
  int _countdownRemaining = 0;
  StreamSubscription<DistanceReading>? _sub;
  Timer? _countdownTimer;
  final List<GuardianEvent> events = [];

  GuardianState get state => _state;
  bool get isActive => _isActive;
  int get countdownRemaining => _countdownRemaining;

  GuardianService({required TvService tv, required DistanceService distance})
      : _tv = tv,
        _distance = distance {
    _initTts();
  }

  Future<void> _initTts() async {
    _tts = FlutterTts();
    await _tts.setLanguage('tr-TR');
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
  }

  void activate() {
    if (_isActive) return;
    _isActive = true;
    _sub = _distance.distanceStream.listen(_onDistance);
    _log('Sistem aktif', GuardianState.idle);
    notifyListeners();
  }

  void deactivate() {
    _isActive = false;
    _sub?.cancel();
    _countdownTimer?.cancel();
    _setState(GuardianState.idle);
    _log('Sistem durduruldu', GuardianState.idle);
  }

  void _onDistance(DistanceReading r) {
    if (!_isActive || !r.faceDetected) return;
    final d = r.distanceCm!;

    switch (_state) {
      case GuardianState.idle:
        if (d < warningDistanceCm) _enterWarning(d);

      case GuardianState.warning:
      case GuardianState.countdown:
        if (d >= safeDistanceCm) _enterSafe();

      case GuardianState.tvOff:
        if (d >= safeDistanceCm) _enterSafeFromOff();
    }
  }

  Future<void> _enterWarning(double dist) async {
    _setState(GuardianState.warning);
    _log('Uyarı: ${dist.round()} cm', GuardianState.warning);

    await _speak('Lütfen mesafenizi koruyun. Televizyona çok yakınsınız.');

    await Future.delayed(const Duration(seconds: 3));
    if (_state == GuardianState.warning) _startCountdown();
  }

  void _startCountdown() {
    _setState(GuardianState.countdown);
    _countdownRemaining = countdownSeconds;
    _log('Geri sayım başladı', GuardianState.countdown);

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      _countdownRemaining--;
      notifyListeners();
      if (_countdownRemaining <= 3 && _countdownRemaining > 0) {
        _speak('$_countdownRemaining');
      }
      if (_countdownRemaining <= 0) {
        t.cancel();
        if (_state == GuardianState.countdown) _turnOff();
      }
    });
  }

  Future<void> _turnOff() async {
    _setState(GuardianState.tvOff);
    _log('TV kapatıldı', GuardianState.tvOff);
    await _speak('Televizyon kapatılıyor.');
    await Future.delayed(const Duration(milliseconds: 800));
    await _tv.powerToggle();
  }

  void _enterSafe() {
    _countdownTimer?.cancel();
    _setState(GuardianState.idle);
    _log('Güvenli mesafe', GuardianState.idle);
  }

  Future<void> _enterSafeFromOff() async {
    _setState(GuardianState.idle);
    _log('Geri döndü - TV açılıyor', GuardianState.idle);
    await _tv.powerToggle();
    await Future.delayed(const Duration(milliseconds: 800));
    await _speak('Harika! Güvenli mesafeye geçtiniz.');
  }

  // ─── Sesli Komut İşleme ───────────────────────────────────────────────────

  Future<void> handleVoiceCommand(String command) async {
    final cmd = command.toLowerCase().trim();
    debugPrint('Sesli komut: $cmd');

    // Türkçe + İngilizce eşleştirme
    if (_has(cmd, ['durdur', 'dur', 'beklet', 'pause', 'duraklat'])) {
      await _tv.pause();
      await _speak('Duraklatıldı.');
    } else if (_has(cmd, ['başlat', 'devam', 'oynat', 'play', 'resume', 'çalıştır'])) {
      await _tv.play();
      await _speak('Devam ediyor.');
    } else if (_has(cmd, ['kapat', 'söndür', 'power off', 'kapa'])) {
      await _tv.powerToggle();
      await _speak('Televizyon kapatıldı.');
    } else if (_has(cmd, ['aç', 'power on', 'aç televizyonu', 'çalıştır'])) {
      await _tv.powerToggle();
      await _speak('Televizyon açıldı.');
    } else if (_has(cmd, ['ses aç', 'volume up', 'sesini aç', 'sesi yükselt'])) {
      for (var i = 0; i < 3; i++) await _tv.volumeUp();
    } else if (_has(cmd, ['ses kıs', 'volume down', 'sesini kıs', 'sesi azalt'])) {
      for (var i = 0; i < 3; i++) await _tv.volumeDown();
    } else if (_has(cmd, ['sessiz', 'mute', 'sustur', 'sesi kes'])) {
      await _tv.mute();
    } else if (_has(cmd, ['ana ekran', 'home', 'anasayfa', 'ana sayfa'])) {
      await _tv.home();
    } else if (_has(cmd, ['geri', 'back'])) {
      await _tv.back();
    } else if (_has(cmd, ['youtube'])) {
      await _tv.openApp('https://www.youtube.com');
      await _speak('YouTube açılıyor.');
    } else if (_has(cmd, ['netflix'])) {
      await _tv.openApp('https://www.netflix.com');
      await _speak('Netflix açılıyor.');
    } else if (_has(cmd, ['disney', 'disney plus'])) {
      await _tv.openApp('https://www.disneyplus.com');
    }

    _log('Komut: $cmd', _state);
  }

  bool _has(String cmd, List<String> keywords) =>
      keywords.any((k) => cmd.contains(k));

  Future<void> _speak(String text) async {
    await _tts.stop();
    await _tts.speak(text);
  }

  void _setState(GuardianState s) {
    _state = s;
    notifyListeners();
  }

  void _log(String msg, GuardianState s) {
    events.insert(0, GuardianEvent(msg, s));
    if (events.length > 30) events.removeLast();
    notifyListeners();
  }

  @override
  void dispose() {
    deactivate();
    _tts.stop();
    super.dispose();
  }
}
