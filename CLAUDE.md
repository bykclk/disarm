# Disarm — iOS CDR fabrika/tycoon oyunu

## Yapı
- `Packages/DisarmCore/` — saf Swift oyun mantığı (UIKit yok). Grid, modüller, dosya modeli, sözleşmeler, ekonomi, simülasyon, offline hesap. `swift test` ile macOS'ta test edilir.
- `Disarm/` — iOS uygulaması. `Game/GameEngine.swift` (@Observable, @MainActor; durum + simülasyon + kayıt), `Game/GameScene.swift` (SpriteKit çizim ve dokunma), `UI/` (SwiftUI HUD, palet, sheet'ler).
- `project.yml` — XcodeGen tanımı. `Disarm.xcodeproj` üretilir, git'e girmez.

## Komutlar
- `make test` — çekirdek testleri (hızlı, önce bunu çalıştır)
- `make build` — simülatör derlemesi
- `make run ARGS="-demo"` — örnek hatla başlat; `-skipHelp`, `-sheet contracts|upgrades|locations|log|module` dev argümanları
- `make screenshot` — ekran görüntüsü `.screens/` altına

## Kurallar
- Oyun kuralı değişiklikleri önce `DisarmCore`'a, testiyle birlikte. UI yalnızca durumu gösterir.
- Swift 6 strict concurrency açık. Motor `@MainActor`; SpriteKit `update` içinden `engine.tick(dt:)` çağrılır.
- Yerelleştirme: koddaki anahtar İngilizce kaynak metin, Türkçe çevirisi String Catalog'da. Çekirdekte `L("...")` (Resources/Localizable.xcstrings, Bundle.module), uygulamada SwiftUI literal'leri otomatik, `String` bağlamında `String(localized:)` (Disarm/Resources/Localizable.xcstrings). Yeni metin eklerken iki yere de gir; enterpolasyonlu anahtarlarda `%lld` (Int) / `%@` (String). Yüzde işaretini argümanlı anahtara doğrudan yazma, önce String'e çevir.
- Dil testi: `xcrun simctl launch <udid> com.omerbuyukcelik.disarm -AppleLanguages "(en)"`.
- `GameState` ve `Simulation` Codable; alan eklerken eski kayıtların bozulmaması için varsayılan değer düşün (şimdilik kayıt uyumsuzsa sıfırdan başlar).
