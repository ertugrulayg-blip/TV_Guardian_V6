// lib/services/tv_service.dart
//
// Google TV Remote uygulamasının kullandığı AYNI protokol.
// Kullanıcıdan tek yapması gereken: TV ekranında çıkan PIN'i girmek.
// Geliştirici modu, ADB, hiçbir şey gerekmez.
//
// Protokol özeti:
//   1. Eşleştirme (bir kez yapılır):
//      - Telefon, TV'ye port 6467'den bağlanır
//      - TV ekranında 6 haneli PIN çıkar
//      - Kullanıcı PIN'i uygulamaya girer
//      - Sertifika oluşturulur, kaydedilir
//   2. Sonraki bağlantılar:
//      - Sertifika ile otomatik bağlanır, PIN gerekmez
//      - Port 6466 üzerinden komut gönderilir

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:androidtvremote/androidtvremote.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TvStatus {
  disconnected,   // Bağlı değil
  connecting,     // Bağlanmaya çalışıyor
  pairing,        // PIN bekleniyor
  connected,      // Hazır
  error,          // Hata
}

class TvService extends ChangeNotifier {
  AndroidTvRemote? _remote;
  TvStatus _status = TvStatus.disconnected;
  String? _tvIp;
  String? _errorMessage;
  bool _isPaired = false;

  // PIN bekleme tamamlayıcısı
  Completer<String>? _pinCompleter;

  TvStatus get status => _status;
  String? get tvIp => _tvIp;
  String? get errorMessage => _errorMessage;
  bool get isConnected => _status == TvStatus.connected;
  bool get needsPin => _status == TvStatus.pairing;

  // ─── Eşleştirme (ilk kurulum) ─────────────────────────────────────────────

  /// TV ile ilk kez eşleştirme başlatır.
  /// TV ekranında PIN çıkar → [waitForPin] ile alınır → [confirmPin] ile doğrulanır.
  Future<bool> startPairing(String tvIp) async {
    _tvIp = tvIp;
    _setStatus(TvStatus.connecting);

    try {
      _remote = AndroidTvRemote(
        clientName: 'TV Koruma',  // TV ekranında bu isim görünür
        host: tvIp,
      );

      // Eşleştirme başlat - TV ekranında PIN çıkar
      await _remote!.startPairing();
      _setStatus(TvStatus.pairing);
      return true;
    } catch (e) {
      _errorMessage = 'TV\'ye bağlanılamadı: ${_friendlyError(e)}';
      _setStatus(TvStatus.error);
      return false;
    }
  }

  /// Kullanıcının TV ekranından okuduğu PIN ile eşleştirmeyi tamamlar.
  Future<bool> confirmPin(String pin) async {
    if (_remote == null) return false;

    try {
      await _remote!.confirmPairingCode(pin);

      // Sertifikayı kaydet (bir daha PIN sormamak için)
      final cert = _remote!.getCertificate();
      await _saveCertificate(cert);
      _isPaired = true;

      // Eşleştirme sonrası komut bağlantısı kur
      await _connectForCommands();
      return true;
    } catch (e) {
      _errorMessage = 'Yanlış PIN. Tekrar deneyin.';
      _setStatus(TvStatus.error);
      return false;
    }
  }

  // ─── Otomatik Bağlantı (eşleşme sonrası) ─────────────────────────────────

  /// Daha önce eşleştirilmiş TV'ye otomatik bağlan (PIN gerekmez).
  Future<bool> connect(String tvIp) async {
    _tvIp = tvIp;
    _setStatus(TvStatus.connecting);

    final cert = await _loadCertificate();
    if (cert == null) {
      // Hiç eşleştirilmemiş → eşleştirme gerekli
      return startPairing(tvIp);
    }

    try {
      _remote = AndroidTvRemote(
        clientName: 'TV Koruma',
        host: tvIp,
        certificate: cert,
      );

      await _connectForCommands();
      return true;
    } catch (e) {
      _errorMessage = _friendlyError(e);
      _setStatus(TvStatus.error);
      // Sertifika geçersiz olabilir, yeniden eşleştir
      await _clearCertificate();
      return false;
    }
  }

  Future<void> _connectForCommands() async {
    await _remote!.connect();
    _setStatus(TvStatus.connected);
    debugPrint('TV bağlandı: $_tvIp');
  }

  void disconnect() {
    _remote?.dispose();
    _remote = null;
    _setStatus(TvStatus.disconnected);
  }

  // ─── Komutlar ─────────────────────────────────────────────────────────────
  // Tüm tuş kodları Android KeyEvent'ten geliyor, TV üreticisinden bağımsız.

  Future<void> _sendKey(int keyCode) async {
    if (!isConnected || _remote == null) return;
    try {
      await _remote!.sendKey(keyCode: keyCode);
    } catch (e) {
      debugPrint('Tuş hatası: $e');
      _handleDisconnect();
    }
  }

  // Güç
  Future<void> powerToggle() => _sendKey(26);   // KEYCODE_POWER

  // Medya
  Future<void> play()      => _sendKey(126);  // KEYCODE_MEDIA_PLAY
  Future<void> pause()     => _sendKey(127);  // KEYCODE_MEDIA_PAUSE
  Future<void> playPause() => _sendKey(85);   // KEYCODE_MEDIA_PLAY_PAUSE
  Future<void> stop()      => _sendKey(86);   // KEYCODE_MEDIA_STOP

  // Ses
  Future<void> volumeUp()   => _sendKey(24);   // KEYCODE_VOLUME_UP
  Future<void> volumeDown() => _sendKey(25);   // KEYCODE_VOLUME_DOWN
  Future<void> mute()       => _sendKey(164);  // KEYCODE_VOLUME_MUTE

  // Navigasyon
  Future<void> home()   => _sendKey(3);    // KEYCODE_HOME
  Future<void> back()   => _sendKey(4);    // KEYCODE_BACK
  Future<void> up()     => _sendKey(19);   // KEYCODE_DPAD_UP
  Future<void> down()   => _sendKey(20);   // KEYCODE_DPAD_DOWN
  Future<void> left()   => _sendKey(21);   // KEYCODE_DPAD_LEFT
  Future<void> right()  => _sendKey(22);   // KEYCODE_DPAD_RIGHT
  Future<void> ok()     => _sendKey(23);   // KEYCODE_DPAD_CENTER

  /// Uygulama aç (deep link ile - uygulama kurulu olmalı)
  Future<void> openApp(String url) async {
    if (!isConnected || _remote == null) return;
    try {
      await _remote!.sendAppLink(url);
    } catch (e) {
      debugPrint('Uygulama açma hatası: $e');
    }
  }

  // ─── Sertifika Kaydetme/Yükleme ───────────────────────────────────────────

  Future<void> _saveCertificate(dynamic cert) async {
    final prefs = await SharedPreferences.getInstance();
    // Sertifikayı JSON olarak kaydet
    await prefs.setString('tv_cert_${_tvIp}', cert.toString());
    await prefs.setString('tv_ip_last', _tvIp ?? '');
    debugPrint('Sertifika kaydedildi');
  }

  Future<dynamic> _loadCertificate() async {
    final prefs = await SharedPreferences.getInstance();
    final certStr = prefs.getString('tv_cert_${_tvIp}');
    if (certStr == null) return null;
    // Sertifika parse - androidtvremote paketinin formatına göre
    try {
      return certStr; // Paket string'i kabul ediyorsa
    } catch (_) {
      return null;
    }
  }

  Future<void> _clearCertificate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('tv_cert_${_tvIp}');
  }

  Future<String?> getSavedTvIp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('tv_ip_last');
  }

  // ─── Yardımcı ─────────────────────────────────────────────────────────────

  void _handleDisconnect() {
    _setStatus(TvStatus.disconnected);
    // 10 saniye sonra yeniden bağlanmayı dene
    Future.delayed(const Duration(seconds: 10), () {
      if (_status != TvStatus.connected && _tvIp != null) {
        connect(_tvIp!);
      }
    });
  }

  void _setStatus(TvStatus s) {
    _status = s;
    _errorMessage = s != TvStatus.error ? null : _errorMessage;
    notifyListeners();
  }

  String _friendlyError(dynamic e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('timeout') || msg.contains('refused')) {
      return 'TV\'ye ulaşılamadı. Aynı WiFi ağında mısınız?';
    }
    if (msg.contains('certificate') || msg.contains('tls')) {
      return 'Güvenlik hatası. Yeniden eşleştirmeyi deneyin.';
    }
    return 'Bağlantı hatası. TV açık ve aynı ağda mı?';
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
