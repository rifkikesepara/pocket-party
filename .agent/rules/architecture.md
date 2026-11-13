# Pocket Party — Mimari ve Kodlama Kuralları

## 1. Teknoloji Yığını ve Dil Kuralları
- **Oyun Motoru:** Godot 4.x (Standart GDScript sürümü).
- **GDScript Standardı:** Tüm değişkenler, parametreler ve dönüş tipleri açıkça belirtilmelidir (`Strict Typing`). `Variant` kullanımından kaçının.
- **Ağ Katmanı:** Yalnızca BLE (Bluetooth Low Energy) ve masaüstü testleri için yerel UDP Mock katmanı kullanılır. İnternet, Wi-Fi Direct veya harici sunucu kodu yazılmaz.

## 2. 16-Byte İkili Paket Protokolü (`PackedByteArray`)
Tüm ağ paketleri tam olarak **16 byte** uzunluğunda olmalıdır:
- `[0]` (`uint8`): Paket Tipi (`0x01`: Eşleşme/Kalibrasyon, `0x02`: Oyun Hamlesi, `0x03`: Tur Sonu, `0x04`: Oyun Sonu)
- `[1]` (`uint8`): Gönderen Oyuncu ID (`0 - 7`)
- `[2]` (`uint8`): Hedef Oyuncu ID (`0 - 7`, `0xFF` = Tüm Masa / AOE)
- `[3]` (`uint8`): Mini Oyun ID (`1 - 24`)
- `[4..5]` (`uint16`): Gönderen Pusula Açısı (`0 - 360`)
- `[6..9]` (`uint32`): Ortak Rastgelelik Tohumu (`Seed`)
- `[10..15]` (`6 byte`): Oyuna özel parametreler ve son byte (`[15]`) XOR Checksum.

## 3. Mini Oyun Mimarisi
- Her yeni mini oyun `res://minigames/base/MiniGameBase.gd` sınıfından türetilmelidir.
- Donanım sensörlerine (`Input.get_magnetometer()`, `Input.get_accelerometer()`) doğrudan mini oyun içinden erişilmez; yalnızca `SensorGestureController` sinyalleri dinlenir.
- Halka açık ortamlarda oynanabilirlik için tüm savurma (`flick`) mekaniklerine paralel olarak dokunmatik kaydırma (`swipe`) desteği zorunludur.