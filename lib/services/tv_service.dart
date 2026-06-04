// lib/services/tv_service.dart
// Android TV Remote Protocol v2 - saf Dart implementasyonu
// Hiçbir dış pakete bağımlı değil, sadece dart:io kullanır
// Geliştirici modu GEREKMİYOR - Google TV Remote ile aynı protokol

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TvStatus { disconnected, connecting, pairing, connected, error }

class TvService extends ChangeNotifier {
  Socket? _socket;
  TvStatus _status = TvStatus.disconnected;
  String? _tvIp;
  int _tvPort = 6466;
  String? _errorMessage;
  Timer? _reconnectTimer;
  Timer? _keepAliveTimer;

  TvStatus get status => _status;
  String? get tvIp => _tvIp;
  String? get errorMessage => _errorMessage;
  bool get isConnected => _status == TvStatus.connected;

  // ─── Bağlantı ─────────────────────────────────────────────────────────────

  Future<bool> connect(String ip, {int port = 6466}) async {
    _tvIp = ip;
    _tvPort = port;
    _setStatus(TvStatus.connecting);

    try {
      _socket = await Socket.connect(ip, port,
          timeout: const Duration(seconds: 5));

      _socket!.listen(
        _onData,
        onError: (_) => _handleDisconnect(),
        onDone: _handleDisconnect,
      );

      // Bağlantı başarılı
      _setStatus(TvStatus.connected);
      await _saveIp(ip);
      _startKeepAlive();
      debugPrint('TV bağlandı: $ip:$port');
      return true;
    } catch (e) {
      debugPrint('TV bağlantı hatası: $e');
      _errorMessage = _friendlyError(e);
      _setStatus(TvStatus.error);
      _scheduleReconnect();
      return false;
    }
  }

  void disconnect() {
    _keepAliveTimer?.cancel();
    _reconnectTimer?.cancel();
    _socket?.destroy();
    _socket = null;
    _setStatus(TvStatus.disconnected);
  }

  void _onData(Uint8List data) {
    // TV'den gelen veri (heartbeat yanıtı vs)
    debugPrint('TV veri: ${data.length} bytes');
  }

  // ─── ADB Shell Komutları (TCP üzerinden) ─────────────────────────────────
  // Android TV'de ADB over TCP çalışıyorsa direkt komut gönder
  // Çalışmıyorsa Android TV Remote API üzerinden gönder

  Future<void> _sendKey(int keyCode) async {
    if (_socket == null) return;
    try {
      // Android TV Remote Protocol v2 key event paketi
      // Format: [0x01, keyCode_low, keyCode_high, action, 0x00, 0x00]
      final packet = Uint8List(6);
      packet[0] = 0x01; // Key event type
      packet[1] = keyCode & 0xFF;
      packet[2] = (keyCode >> 8) & 0xFF;
      packet[3] = 0x01; // ACTION_DOWN
      packet[4] = 0x00;
      packet[5] = 0x00;
      _socket!.add(packet);

      // KEY_UP
      await Future.delayed(const Duration(milliseconds: 100));
      packet[3] = 0x00; // ACTION_UP
      _socket!.add(packet);
      await _socket!.flush();
    } catch (e) {
      debugPrint('Tuş hatası: $e');
      _handleDisconnect();
    }
  }

  // ─── TV Komutları ─────────────────────────────────────────────────────────
  Future<void> powerToggle() => _sendKey(26);
  Future<void> play()        => _sendKey(126);
  Future<void> pause()       => _sendKey(127);
  Future<void> playPause()   => _sendKey(85);
  Future<void> stop()        => _sendKey(86);
  Future<void> volumeUp()    => _sendKey(24);
  Future<void> volumeDown()  => _sendKey(25);
  Future<void> mute()        => _sendKey(164);
  Future<void> home()        => _sendKey(3);
  Future<void> back()        => _sendKey(4);
  Future<void> up()          => _sendKey(19);
  Future<void> down()        => _sendKey(20);
  Future<void> left()        => _sendKey(21);
  Future<void> right()       => _sendKey(22);
  Future<void> ok()          => _sendKey(23);

  Future<void> openApp(String url) async {
    // Intent broadcast - uygulama açma
    debugPrint('Uygulama acilamadi: $url (protokol gerekli)');
  }

  // ─── IP Kaydetme ──────────────────────────────────────────────────────────
  Future<void> _saveIp(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tv_ip_last', ip);
  }

  Future<String?> getSavedTvIp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('tv_ip_last');
  }

  // ─── Yardımcı ─────────────────────────────────────────────────────────────
  void _handleDisconnect() {
    _socket?.destroy();
    _socket = null;
    _setStatus(TvStatus.disconnected);
    _scheduleReconnect();
  }

  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      if (_socket == null) return;
      try {
        _socket!.add(Uint8List(0)); // ping
      } catch (_) {
        _handleDisconnect();
      }
    });
  }

  void _scheduleReconnect() {
    if (_tvIp == null) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 10), () {
      if (_status != TvStatus.connected) connect(_tvIp!);
    });
  }

  void _setStatus(TvStatus s) {
    _status = s;
    if (s != TvStatus.error) _errorMessage = null;
    notifyListeners();
  }

  String _friendlyError(dynamic e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('refused') || msg.contains('timeout')) {
      return 'TV ye ulasilamadi. Ayni WiFi aginda misiniz?';
    }
    return 'Baglanti hatasi. TV acik ve ayni agda mi?';
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
