SIM ?= iPhone 17
BUNDLE = com.omerbuyukcelik.disarm
DERIVED = $(HOME)/Library/Developer/Xcode/DerivedData

.PHONY: gen build test run screenshot clean

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

screenshot: ## Çalışan simülatörden ekran görüntüsü
	mkdir -p .screens && xcrun simctl io $(UDID) screenshot .screens/$$(date +%H%M%S).png

clean:
	rm -rf Disarm.xcodeproj Packages/DisarmCore/.build
