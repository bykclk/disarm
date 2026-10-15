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

run: build ## Simülatörde başlat (ARGS="-demo" ile örnek hat)
	$(eval UDID := $(shell xcrun simctl list devices available | grep "$(SIM) (" | head -1 | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/'))
	xcrun simctl boot $(UDID) 2>/dev/null || true
	xcrun simctl install $(UDID) "$$(find $(DERIVED) -path '*Disarm-*/Build/Products/Debug-iphonesimulator/Disarm.app' -maxdepth 6 | head -1)"
	xcrun simctl terminate $(UDID) $(BUNDLE) 2>/dev/null || true
	xcrun simctl launch $(UDID) $(BUNDLE) $(ARGS)
	open -a Simulator

screenshot: ## Çalışan simülatörden ekran görüntüsü
	$(eval UDID := $(shell xcrun simctl list devices available | grep "$(SIM) (" | head -1 | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/'))
	mkdir -p .screens && xcrun simctl io $(UDID) screenshot .screens/$$(date +%H%M%S).png

clean:
	rm -rf Disarm.xcodeproj Packages/DisarmCore/.build
