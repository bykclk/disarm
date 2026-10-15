# Disarm

CDR (Content Disarm & Reconstruction) temalı, iOS için fabrika/tycoon oyunu. Müşteri dosyaları bantta akar; oyuncu ayrıştırıcı, filtre, dönüştürücü ve paketleyici modülleriyle dosyaları temizleyip teslim eder. Oyunun gerilimi gerçek CDR ikilemidir: agresif temizlersen dosya bozulur ve müşteri ödemez, gevşek bırakırsan zararlı kaçar ve ihlal cezası yersin.

## Oynanış özeti
- **Dosyalar**: kap (PDF, DOCX, XLSX, PNG, ZIP) + parçalar (metin, görsel, formül, makro, betik, gömülü dosya, gizli veri, bilinmeyen). Parçaların derinliği var: ZIP içinde ZIP bir kat içeride, polyglot dosyanın ikinci kimliği gizli.
- **Modüller**: İmza Tarayıcı (ucuz, kapalı dosyada çalışır, sadece bilinen tehditler), Ayrıştırıcı (açar; seviye 2 iç içe, seviye 3 polyglot), Filtre (makro/betik/gömülü), Dönüştürücü (gizli veri ve bilinmeyeni yok eder; düşük seviyede görsel kalitesi düşer, formüller düzleşir), Paketleyici (kapatır; şart), Yönlendirici (kap türüne göre sağa ayırır), Karantina.
- **Sözleşmeler**: Muhasebe (formül korunsun, makro silinsin), Hukuk (metin korunsun), Tasarım Ajansı (görsel kalitesi ≥ %85), Banka (sıfır aktif içerik), Kamu (air-gapped: tarayıcı kör).
- **Tehdit merdiveni**: makro → betik → ZIP içinde ZIP → polyglot/gizli veri → imzasız bilinmeyen.
- **Tycoon**: para, itibar, modül seviyeleri, bant hızı, giriş hızı, dört mekân (Küçük Ofis 7×10 → Şirket 8×12 → Banka 9×13 → Kamu 10×14). Offline kazanç son kazanç hızına göre, 4 saatle sınırlı.

## Geliştirme
Gereksinimler: Xcode 27, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
make test                 # çekirdek testleri
make run ARGS="-demo"     # simülatörde örnek hatla başlat
```

Proje dosyası `project.yml`'den üretilir (`make gen`), repoya girmez.
