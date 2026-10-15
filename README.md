# Disarm

CDR (Content Disarm & Reconstruction) temalı, iOS için fabrika/tycoon oyunu. Müşteri dosyaları bantta akar; oyuncu ayrıştırıcı, filtre, dönüştürücü ve paketleyici modülleriyle dosyaları temizleyip teslim eder. Oyunun gerilimi gerçek CDR ikilemidir: agresif temizlersen dosya bozulur ve müşteri ödemez, gevşek bırakırsan zararlı kaçar ve ihlal cezası yersin.

## Oynanış özeti
- **Dosyalar**: kap (PDF, DOCX, XLSX, PNG, ZIP) + parçalar (metin, görsel, formül, makro, betik, gömülü dosya, gizli veri, bilinmeyen). Parçaların derinliği var: ZIP içinde ZIP bir kat içeride, polyglot dosyanın ikinci kimliği gizli.
- **Modüller**: İmza Tarayıcı (ucuz, kapalı dosyada çalışır, sadece bilinen tehditler), Ayrıştırıcı (açar; seviye 2 iç içe, seviye 3 polyglot), Filtre (makro/betik/gömülü), Dönüştürücü (gizli veri ve bilinmeyeni yok eder; düşük seviyede görsel kalitesi düşer, formüller düzleşir), Paketleyici (kapatır; şart), Yönlendirici (kap türüne ya da şifreye göre sağa ayırır), Karantina, Kum Havuzu (yalnızca Veri Merkezi'nde: imzasız zararlıyı dosyayı açmadan ve bozmadan yok eder; yavaş, pahalı, şifreli ve polyglot'a kör).
- **Sözleşmeler**: Muhasebe (formül korunsun, makro silinsin), Hukuk (metin korunsun), Tasarım Ajansı (görsel kalitesi ≥ %85), Yazılım Evi (betikler kaynak kod: korunsun, yalnızca zararlılar gitsin → tarayıcı), Hastane (görsel ≥ %90 ama gizli hasta verisi silinsin → seviye 3 dönüştürücü), Banka (sıfır aktif içerik, şifreli dosya reddedilir), Kamu (air-gapped: tarayıcı kör), Adli Bilişim (görsel ≥ %97, formüller sağlam: dönüştürücü yasak, kum havuzu şart). Beş mekânda 17 sözleşme.
- **Tehdit merdiveni**: makro → betik → ZIP içinde ZIP → polyglot/gizli veri → imzasız bilinmeyen ve üç kat iç içe arşiv → şifreli arşiv (hiçbir modül açamaz; yönlendirici "şifrelileri ayır" moduyla karantinaya gönderilir, zararsız şifreliler de gittiği için gelir kaybı).
- **Tycoon**: para, itibar, modül seviyeleri, bant hızı, giriş hızı, beş mekân (Küçük Ofis 7×10 → Şirket 8×12 → Banka 9×13 → Kamu 10×14 → Veri Merkezi 11×15). Offline kazanç son kazanç hızına göre, 4 saatle sınırlı.
- **Kampanya ve prestij**: beş mekândaki 17 sözleşme bir kez bitince kampanya tamamlanır (özet ekranı, en hızlı süre). Oyun sonsuz sürer; istenirse prestij ile sıfırdan başlanır: her prestij seviyesi ödemeyi %15, dosya akışını %10 artırır ve başlangıç parası ekler. Toplam istatistikler korunur.

## Oyun hissi
- Prosedürel ses: efektler ve 23 saniyelik ambient döngü bir Swift betiğiyle sentezlenir, dışarıdan ses dosyası yok. Sessiz anahtarına uyar, kullanıcının müziğiyle karışır. Menüden kapatılabilir.
- Efektler: çalışan modül parlar, yerleştirme pop-in, çıkarılan parça etiketi uçar, teslimatta para etiketi ve parçacık, ihlalde sarsıntı ve kırmızı flaş, sözleşme bitiminde konfeti.
- Diller: Türkçe ve İngilizce (String Catalog).

## Geliştirme
Gereksinimler: Xcode 27, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
make test                 # çekirdek testleri
make run ARGS="-demo"     # simülatörde örnek hatla başlat
```

Proje dosyası `project.yml`'den üretilir (`make gen`), repoya girmez.
