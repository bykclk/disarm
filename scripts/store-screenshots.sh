#!/bin/sh
# App Store ekran görüntüleri: 6,9" iPhone simülatöründe (1320×2868) demo durumlarıyla, TR ve EN.
# Çıktı: .store/screenshots/<locale>/APP_IPHONE_67/NN-<ad>.png  (ascelerate media upload düzeni)
# Kullanım: scripts/store-screenshots.sh [simülatör adı]   (önce `make build`)
set -e
SIM_NAME="${1:-iPhone 17 Pro Max}"
BUNDLE=com.omerbuyukcelik.disarm
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/.store/screenshots"
UDID=$(xcrun simctl list devices available | grep "$SIM_NAME (" | head -1 | grep -oE '[0-9A-F-]{36}')
[ -n "$UDID" ] || { echo "Simülatör bulunamadı: $SIM_NAME"; exit 1; }
APP=$(/bin/ls -td "$HOME"/Library/Developer/Xcode/DerivedData/Disarm-*/Build/Products/Debug-iphonesimulator/Disarm.app | head -1)
[ -n "$APP" ] || { echo "Simülatör derlemesi yok: make build"; exit 1; }

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4
xcrun simctl install "$UDID" "$APP"

# ad | bekleme sn | argümanlar
shots='
01-office|7|-demo -skipHelp
02-bank|8|-demoBank
03-datacenter|7|-demoDC
04-contracts|3|-demoBank -sheet contracts
05-campaign|3|-demoEnd
06-upgrades|3|-demoDC -sheet upgrades
'
for lang in tr en; do
  case $lang in tr) loc=tr;; en) loc=en-US;; esac
  dir="$OUT/$loc/APP_IPHONE_67"; mkdir -p "$dir"
  echo "$shots" | while IFS='|' read -r name wait args; do
    [ -n "$name" ] || continue
    xcrun simctl terminate "$UDID" $BUNDLE 2>/dev/null || true
    # shellcheck disable=SC2086
    xcrun simctl launch "$UDID" $BUNDLE $args -AppleLanguages "($lang)" >/dev/null
    sleep "$wait"
    xcrun simctl io "$UDID" screenshot "$dir/$name.png" >/dev/null
    echo "$loc/$name.png"
  done
done
xcrun simctl terminate "$UDID" $BUNDLE 2>/dev/null || true
sips -g pixelWidth -g pixelHeight "$OUT/en-US/APP_IPHONE_67/01-office.png" | tail -2
