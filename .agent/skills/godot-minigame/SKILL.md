---
name: godot-minigame
description: Pocket Party için MiniGameBase sınıfından türeyen yeni bir Godot 4.x parti mini oyunu sahnesi ve betiği oluşturur.
---

# Yeni Mini Oyun Oluşturma Prosedürü

1. `res://minigames/<oyun_adi>/` klasörü altında `<OyunAdi>.gd` ve `<OyunAdi>.tscn` dosyalarını oluştur.
2. Betiği `extends MiniGameBase` ile başlat ve `class_name` tanımla.
3. `_ready()` içinde `SensorGestureController` sinyallerini (`aim_target_changed`, `flick_detected`, `tilt_changed`, `device_flipped`) bağla.
4. Ağ üzerinden veri gönderirken `PartyNetworkBridge.send_action(target_id, action_code, payload_bytes)` metodunu kullan; ham `PackedByteArray` oluşturma.
5. Masaüstü testleri için klavye kısayollarını (`Space` = Savurma, `Sol/Sağ Ok` = Hedef Değiştirme) `MiniGameBase` üzerinden miras al.
