# 📺 TV Koruma

Çocuğun TV'ye yaklaşmasını otomatik algılar, uyarı verir, gerekirse TV'yi kapatır.

---

## Kurulum (3 adım, IP adresi yok)

### 1. Uygulamayı yükle
```
flutter pub get
flutter run --release
```

### 2. Uygulama açılınca otomatik TV taraması başlar
- Aynı WiFi'daki tüm Android TV'ler listede görünür
- Listeden kendi TV'ne dokun

### 3. TV ekranında PIN çıkar → Gir → Bitti
- TV ekranında 6 haneli kod görünür
- Uygulamaya gir → Onayla
- **Bir daha sorulmaz**, otomatik bağlanır

---

## Sistem nasıl çalışır

```
Çocuk 150cm'den yaklaştı
  → Sesli uyarı: "Lütfen mesafenizi koruyun"
  → 10 saniye bekler
  → Hâlâ yakınsa TV kapanır
  → Çocuk geri gidince TV otomatik açılır
```

---

## TV keşif yöntemi

1. **mDNS (öncelikli):** Android TV'ler ağa `_androidtvremote2._tcp` servisi
   yayınlar. Bu Google TV Remote uygulamasının da kullandığı yöntem.
   Genellikle ~3 saniyede bulur.

2. **Ağ taraması (yedek):** mDNS çalışmazsa 192.168.x.1-254 arasını tarar,
   port 6466'ya bağlanabilen cihazları TV sayar. ~15-30 saniye sürer.

---

## Sesli komutlar

| Söyle | Ne yapar |
|-------|----------|
| "durdur" / "pause" | Duraklat |
| "başlat" / "play" | Devam ettir |
| "kapat" | TV kapat |
| "ses aç" / "volume up" | Sesi artır |
| "ses kıs" / "volume down" | Sesi azalt |
| "sessiz" / "mute" | Sessiz |
| "youtube" | YouTube aç |
| "netflix" | Netflix aç |
