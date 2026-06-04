// lib/services/tv_discovery_service.dart
//
// Aynı WiFi ağındaki tüm Android TV'leri otomatik keşfeder.
// Kullanıcı hiçbir IP adresi girmez.
//
// Nasıl çalışır:
//   Android TV'ler ağa "_androidtvremote2._tcp" mDNS servisi yayınlar.
//   Biz bu servisi dinleyip TV'nin adını ve IP'sini otomatik buluyoruz.
//   Bu, Google TV Remote uygulamasının da kullandığı yöntem.
//
// Yedek yöntem (mDNS çalışmazsa):
//   Ağ subnet'ini tararız: 192.168.1.1 → 192.168.1.254
//   Port 6466'ya bağlanabilenleri Android TV sayarız.

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:network_info_plus/network_info_plus.dart';

class DiscoveredTv {
  final String name;   // "Oturma Odası TV" gibi
  final String ip;
  final int port;

  const DiscoveredTv({
    required this.name,
    required this.ip,
    required this.port,
  });

  @override
  String toString() => '$name ($ip)';
  
  @override
  bool operator ==(Object other) =>
      other is DiscoveredTv && other.ip == ip;

  @override
  int get hashCode => ip.hashCode;
}

class TvDiscoveryService extends ChangeNotifier {
  // Android TV'lerin mDNS servis adı — Google'ın resmi protokolü
  static const String _mdnsService = '_androidtvremote2._tcp';
  static const int _tvRemotePort = 6466;

  final List<DiscoveredTv> _found = [];
  bool _isScanning = false;
  String _scanStatus = '';

  List<DiscoveredTv> get foundTvs => List.unmodifiable(_found);
  bool get isScanning => _isScanning;
  String get scanStatus => _scanStatus;
  bool get hasResults => _found.isNotEmpty;

  // ─── Ana Keşif ────────────────────────────────────────────────────────────

  Future<void> discover() async {
    _found.clear();
    _setScanning(true, 'Android TVler aranıyor...');

    // Önce mDNS ile dene (hızlı, ~3 saniye)
    await _discoverViaMdns();

    if (_found.isEmpty) {
      // mDNS bulamazsa ağ taraması yap (yavaş ama güvenilir)
      _setStatus('mDNS bulunamadı, ağ taranıyor...');
      await _discoverViaScan();
    }

    _setScanning(false,
        _found.isEmpty ? 'TV bulunamadı' : '${_found.length} TV bulundu');
  }

  // ─── Yöntem 1: mDNS (Zeroconf) ───────────────────────────────────────────

  Future<void> _discoverViaMdns() async {
    final client = MDnsClient(
      rawDatagramSocketFactory: (dynamic host, int port,
          {bool? reuseAddress, bool? reusePort, int? ttl}) {
        return RawDatagramSocket.bind(host, port,
            reuseAddress: reuseAddress ?? true,
            reusePort: reusePort ?? false,
            ttl: ttl ?? 255);
      },
    );

    try {
      await client.start();
      _setStatus('mDNS ile TV aranıyor...');

      // PTR kaydı: "_androidtvremote2._tcp.local" adını sorgula
      await for (final PtrResourceRecord ptr in client.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(_mdnsService),
      ).timeout(const Duration(seconds: 5), onTimeout: (_) {})) {
        
        // SRV kaydı: IP ve port bilgisi
        await for (final SrvResourceRecord srv in client.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(ptr.domainName),
        ).timeout(const Duration(seconds: 3), onTimeout: (_) {})) {
          
          // A kaydı: gerçek IP adresi
          await for (final IPAddressResourceRecord ip in client.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(srv.target),
          ).timeout(const Duration(seconds: 3), onTimeout: (_) {})) {
            
            final tv = DiscoveredTv(
              name: _cleanName(ptr.domainName),
              ip: ip.address.address,
              port: srv.port,
            );

            if (!_found.contains(tv)) {
              _found.add(tv);
              debugPrint('mDNS TV bulundu: $tv');
              notifyListeners();
            }
          }
        }
      }
    } catch (e) {
      debugPrint('mDNS hata: $e');
    } finally {
      client.stop();
    }
  }

  // ─── Yöntem 2: Ağ Taraması (yedek) ──────────────────────────────────────

  Future<void> _discoverViaScan() async {
    final subnet = await _getSubnet();
    if (subnet == null) {
      _setStatus('Ağ bilgisi alınamadı');
      return;
    }

    _setStatus('Ağ taranıyor: $subnet.0/24');
    debugPrint('Subnet taraması: $subnet');

    // 1-254 arasındaki tüm IP'leri paralel tara
    // Her IP'de port 6466'ya bağlanmayı dene
    final futures = <Future>[];
    for (int i = 1; i <= 254; i++) {
      final ip = '$subnet.$i';
      futures.add(_checkTvPort(ip));

      // 20'şer gruplar halinde tara (flood önleme)
      if (futures.length >= 20) {
        await Future.wait(futures);
        futures.clear();
        _setStatus('Taranıyor... $ip');
      }
    }
    if (futures.isNotEmpty) await Future.wait(futures);
  }

  Future<void> _checkTvPort(String ip) async {
    try {
      final socket = await Socket.connect(ip, _tvRemotePort,
          timeout: const Duration(milliseconds: 400));
      socket.destroy();

      // Port açık = Android TV olabilir
      final tv = DiscoveredTv(
        name: 'Android TV ($ip)',
        ip: ip,
        port: _tvRemotePort,
      );

      if (!_found.contains(tv)) {
        _found.add(tv);
        debugPrint('Port tarama TV bulundu: $ip');
        notifyListeners();
      }
    } catch (_) {
      // Bağlanamadı = TV değil, geç
    }
  }

  // ─── Yardımcı ─────────────────────────────────────────────────────────────

  Future<String?> _getSubnet() async {
    try {
      final info = NetworkInfo();
      final ip = await info.getWifiIP();
      if (ip == null) return null;
      // "192.168.1.105" → "192.168.1"
      final parts = ip.split('.');
      if (parts.length != 4) return null;
      return '${parts[0]}.${parts[1]}.${parts[2]}';
    } catch (_) {
      return null;
    }
  }

  String _cleanName(String domainName) {
    // "_androidtvremote2._tcp.local" kısmını temizle
    return domainName
        .replaceAll('.$_mdnsService.local', '')
        .replaceAll('._androidtvremote2._tcp.local', '')
        .replaceAll('%20', ' ')
        .trim();
  }

  void _setScanning(bool scanning, String status) {
    _isScanning = scanning;
    _scanStatus = status;
    notifyListeners();
  }

  void _setStatus(String status) {
    _scanStatus = status;
    notifyListeners();
  }

  void clear() {
    _found.clear();
    notifyListeners();
  }
}
