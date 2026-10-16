# Mağaza paketi

App Store Connect'e gidecek metinler ve yayın adımları. Ekran görüntüleri `scripts/store-screenshots.sh` ile üretilir (`.store/`, git dışı).

## Dosyalar
- `app-info.json` — uygulama adı, alt başlık, gizlilik politikası URL'si (TR ve EN). `ascelerate apps app-info import <app> --file store/app-info.json`
- `localizations.json` — sürüm açıklaması, anahtar kelimeler, yenilikler, tanıtım metni, destek URL'si. `ascelerate apps localizations import <app> --file store/localizations.json`
- `../docs/privacy.html`, `../docs/support.html` — gizlilik politikası ve destek sayfası (bir yerde yayınlanmalı; GitHub Pages yeterli). `REPLACE-ME` alanları o adreslerle doldurulur.

## Sabit kararlar
- Kategori: Games → Strategy (ikincil: Simulation)
- Yaş sınıfı: 4+ (şiddet, kumar, reklam, kullanıcı içeriği yok)
- Gizlilik etiketi: "Veri toplanmıyor" (ağ erişimi yok, analitik yok, hesap yok)
- İhracat uyumluluğu: `ITSAppUsesNonExemptEncryption = false` (Info.plist)
- Cihaz: yalnızca iPhone (TARGETED_DEVICE_FAMILY 1); iPad düzeni test edilmedi
- Fiyat: karar bekliyor (öneri: ücretsiz, satın alma yok)

## Yayın adımları
1. `make test` ve `make build` yeşil; `scripts/store-screenshots.sh` ile görüntüler.
2. Arşiv: `make archive` → `.store/Disarm.xcarchive`; `make export` → `.store/export/Disarm.ipa` (App Store imzası, otomatik profil).
3. App Store Connect'te uygulama kaydı (ad "Disarm", bundle `com.omerbuyukcelik.disarm`), ardından `ascelerate` ile metin ve görüntü yükleme, build ekleme, ön kontrol ve gönderim; ya da Xcode Organizer ile yükleme.
4. Önce TestFlight (iç test), sonra inceleme.
