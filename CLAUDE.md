# Disarm — iOS CDR fabrika/tycoon oyunu

## Yapı
- `Packages/DisarmCore/` — saf Swift oyun mantığı (UIKit yok). Grid, modüller, dosya modeli, sözleşmeler, ekonomi, simülasyon, offline hesap. `swift test` ile macOS'ta test edilir.
- `Disarm/` — iOS uygulaması. `Game/GameEngine.swift` (@Observable, @MainActor; durum + simülasyon + kayıt), `Game/GameScene.swift` (SpriteKit çizim ve dokunma), `UI/` (SwiftUI HUD, palet, sheet'ler).
- `project.yml` — XcodeGen tanımı. `Disarm.xcodeproj` üretilir, git'e girmez.

## Komutlar
- `make test` — çekirdek testleri (hızlı, önce bunu çalıştır)
- `make build` — simülatör derlemesi
- `make run ARGS="-demo"` — örnek hatla başlat; `-demoBank` (Özel Bankacılık, şifreli dosyalar, yönlendirici→karantina), `-demoEnd` (kampanyası bitmiş durum, prestij akışı), `-demoDC` (Veri Merkezi, kum havuzu hattı), `-demoBelt` (modülsüz S bant, köşe görsel testi), `-demoSiteDone` (ofis bitmiş, şirket kilitli: sıradaki mekân yönlendirmesi), `-fresh` (kayıt yok sayılır, seviye 1, kilitler görünür), `-skipHelp`, `-sheet contracts|upgrades|locations|log|campaign|module` dev argümanları
- `make device ARGS="..."` — bağlı iPhone'a imzalı Debug derlemesi yükle ve başlat (ekip `project.yml`'de; `DEVICE=<udid>` ile cihaz seç)
- `make screenshot` — ekran görüntüsü `.screens/` altına
- `-fps` — sahnede fps/çizim/düğüm sayacı, SwiftUI gövde sıklığı günlükte `[render]` satırları (`xcrun simctl spawn <udid> log stream --predicate 'process == "Disarm"'`). Bu Mac'te `timeout` yok; süreli yakalama için arka plan + `sleep` + `kill`.

## Ses ve efektler
- Sesler `scripts/make-sounds.swift` ile sentezlenir → `Disarm/Resources/Sounds/*.wav` (git'te). Yeni efekt: betiğe `sfx(...)` ekle, `AudioManager.Sfx` enum'una aynı adı ekle, betiği çalıştır.
- Görsel efektler: motor `fx: [FxEvent]` kuyruğuna yazar, `GameScene.drainFx()` her karede tüketir. Yeni efekt için önce `FxEvent` case'i.

## İlerleme
- `DisarmCore/Progression.swift`: XP (kabul edilen teslimat 1+tier/3, sözleşme itibar×2, başarım ödülü), seviye `10·(n−1)(n+1)`, modül kilitleri `ModuleKind.requiredLevel`, yükseltme kademeleri `Progression.requiredLevel(forUpgradeTo:)` (3 ve 6), başarımlar `Achievement` (koşul `isMet`, ödül para+XP, `claimAchievements`). Olaylar `.levelUp`, `.achievementUnlocked`.
- Yeni modül eklerken `requiredLevel` ver; yeni başarım eklerken `isMet` için gerekli istatistiği `Stats`'a ekle. Eski kayıtlarda XP `SaveMigrator.repair` ile istatistiklerden türetilir (`xpDerived`).
- Testlerde yerleşim kuran senaryolar `s.xp = 100_000` ile kilitleri aşar; hız testi `LevelTests.officePacing...`.

## Öğretici
- Küçük ofisin ilk sözleşmesi: `GameEngine.tutorialStep` (durumdan türeyen 5 adım, ilk teslimatta biter).
- Sonrası: `DisarmCore/Hints.swift` içindeki tek seferlik ipucu kartları. Yeni ipucu için `Hint` case'i + `applies(to:)` + `text` (L, iki katalog) + `icon`, isteğe bağlı `action`; görülenler `GameState.seenHints`. Test: `HintTests.everyHintHasTextAndIsReachable`.

## Erişilebilirlik
- SpriteKit sahnesi VoiceOver'a kapalı; `GridAccessibilityOverlay` (ContentView) yalnızca VoiceOver açıkken her hücreyi etiket + eylemle sunar, geometrisi `GameScene.relayout` ile aynı (12 pt pay, kare hücre, ortalı).
- HUD ve palet `dynamicTypeSize(...accessibility1)` ile sınırlı; palet düğmeleri `minWidth/minHeight`, sabit `.system(size:)` kullanma. Test: `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityM`.
- iPad destekli (1,2); düzen aynı, ızgara ölçeklenir. Test: iPad Pro 13-inch simülatörü.

## Kurallar
- Oyun kuralı değişiklikleri önce `DisarmCore`'a, testiyle birlikte. UI yalnızca durumu gösterir.
- Swift 6 strict concurrency açık. Motor `@MainActor`; SpriteKit `update` içinden `engine.tick(dt:)` çağrılır.
- Yerelleştirme: koddaki anahtar İngilizce kaynak metin, Türkçe çevirisi String Catalog'da. Çekirdekte `L("...")` (Resources/Localizable.xcstrings, Bundle.module), uygulamada SwiftUI literal'leri otomatik, `String` bağlamında `String(localized:)` (Disarm/Resources/Localizable.xcstrings). Yeni metin eklerken iki yere de gir; enterpolasyonlu anahtarlarda `%lld` (Int) / `%@` (String). Yüzde işaretini argümanlı anahtara doğrudan yazma, önce String'e çevir.
- Dil testi: `xcrun simctl launch <udid> com.omerbuyukcelik.disarm -AppleLanguages "(en)"`.
- Kayıt: `SaveCodec` (DisarmCore/SaveFile.swift) sürümlü `SaveFile` yazar ve toleranslı okur. `GameState`, `Grid`, `Module`, `Stats`, `ContractProgress`, `Simulation` için `init(from:)` elle yazılmıştır: eksik alan varsayılan alır, tanınmayan enum/modül atılır, `sim` çözülemezse yalnız bant sıfırlanır, `SaveMigrator.repair` mekân boyutu/giriş-çıkış/seviye tutarsızlıklarını düzeltir. Yeni alan eklerken ilgili `init(from:)`'a `decodeOr` satırı ekle; şekil değişiyorsa `SaveFile.currentVersion` artır ve `SaveCodec.migrate`'e adım yaz. Testi `SaveFileTests`.
