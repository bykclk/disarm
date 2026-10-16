SIM ?= iPhone 17
BUNDLE = com.omerbuyukcelik.disarm
DERIVED = $(HOME)/Library/Developer/Xcode/DerivedData
# Bağlı fiziksel cihaz (ilk eşleşmiş iPhone). DEVICE=<udid> ile geçersiz kılınabilir.
DEVICE ?= $(shell xcrun devicectl list devices 2>/dev/null | grep -i physical | grep -oE '[0-9A-F]{8}-[0-9A-F]{16}' | head -1)
DEVICE_APP = $(shell ls -td $(DERIVED)/Disarm-*/Build/Products/Debug-iphoneos/Disarm.app 2>/dev/null | head -1)

.PHONY: gen build test run screenshot device device-build archive export store-screenshots clean

gen: ## project.yml -> Disarm.xcodeproj
	xcodegen generate

test: ## Çekirdek testleri (macOS, hızlı)
	cd Packages/DisarmCore && swift test

build: gen ## Simülatör için derle
	xcodebuild -project Disarm.xcodeproj -scheme Disarm -destination 'platform=iOS Simulator,name=$(SIM)' -configuration Debug build CODE_SIGNING_ALLOWED=NO | grep -E "error:|warning: .*Disarm/|BUILD"

# Simülatör kimliği. GNU make 3.81 $(shell ...) içindeki tek parantezi sayar, o yüzden değişkenden gelir.
OP := (
UDID = $(shell xcrun simctl list devices available | grep "$(SIM) $(OP)" | head -1 | grep -oE '[A-F0-9-]{36}')
# En son derlenen uygulama paketi (birden fazla DerivedData klasörü olabilir).
APP = $(shell ls -td $(DERIVED)/Disarm-*/Build/Products/Debug-iphonesimulator/Disarm.app 2>/dev/null | head -1)

run: build ## Simülatörde başlat (ARGS="-demo" ile örnek hat)
	xcrun simctl boot $(UDID) 2>/dev/null || true
	xcrun simctl install $(UDID) "$(APP)"
	xcrun simctl terminate $(UDID) $(BUNDLE) 2>/dev/null || true
	xcrun simctl launch $(UDID) $(BUNDLE) $(ARGS)
	open -a Simulator 2>/dev/null || true

device-build: gen ## Bağlı iPhone için imzalı Debug derlemesi (profil otomatik)
	@test -n "$(DEVICE)" || { echo "Bağlı cihaz yok: xcrun devicectl list devices"; exit 1; }
	xcodebuild -project Disarm.xcodeproj -scheme Disarm -destination 'id=$(DEVICE)' -configuration Debug build -allowProvisioningUpdates | grep -E "error:|warning: .*Disarm/|BUILD"

device: device-build ## Bağlı iPhone'a yükle ve başlat (ARGS="-demo" ile)
	xcrun devicectl device install app --device $(DEVICE) "$(DEVICE_APP)" | grep -E "installationURL|rror" || true
	xcrun devicectl device process launch --terminate-existing --device $(DEVICE) $(BUNDLE) $(if $(ARGS),-- $(ARGS),)

archive: gen ## App Store için Release arşivi → .store/Disarm.xcarchive
	xcodebuild -project Disarm.xcodeproj -scheme Disarm -configuration Release -destination 'generic/platform=iOS' -archivePath .store/Disarm.xcarchive archive -allowProvisioningUpdates | grep -E "error:|warning: .*Disarm/|ARCHIVE"

export: ## Arşivden App Store imzalı .ipa → .store/export/Disarm.ipa
	xcodebuild -exportArchive -archivePath .store/Disarm.xcarchive -exportPath .store/export -exportOptionsPlist scripts/ExportOptions.plist -allowProvisioningUpdates | grep -E "error:|EXPORT|Exported"

store-screenshots: build ## Mağaza ekran görüntüleri (6,9", TR+EN) → .store/screenshots
	sh scripts/store-screenshots.sh

screenshot: ## Çalışan simülatörden ekran görüntüsü
	mkdir -p .screens && xcrun simctl io $(UDID) screenshot .screens/$$(date +%H%M%S).png

clean:
	rm -rf Disarm.xcodeproj Packages/DisarmCore/.build
