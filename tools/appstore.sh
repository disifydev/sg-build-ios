#!/bin/bash
# Снимки для App Store на iPhone 17 Pro Max (1320×2868), светлая тема, демо-данные → tools/appstore.py
set -e
BUNDLE_ID=${BUNDLE_ID:-dev.disify.batch}
to() { perl -e 'alarm shift; exec @ARGV' "$@"; }
LIST=$(xcrun simctl list devices available)
UDID=$(echo "$LIST" | grep -E "^ +iPhone 17 Pro Max \(" | head -1 | sed -E 's/.*\(([0-9A-Fa-f-]{36})\).*/\1/')
[ -n "$UDID" ] || UDID=$(echo "$LIST" | grep -E "^ +iPhone 16 Pro Max \(" | head -1 | sed -E 's/.*\(([0-9A-Fa-f-]{36})\).*/\1/')
echo "$LIST" | grep "$UDID"
xcrun simctl boot "$UDID" || true
for i in $(seq 1 60); do xcrun simctl list devices | grep "$UDID" | grep -q Booted && break; sleep 3; done
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 || true
xcrun simctl ui "$UDID" appearance light || true
xcrun simctl install "$UDID" build/dd/Build/Products/Debug-iphonesimulator/Sguardo.app
mkdir -p raw-appstore
for w in 1 2; do to 90 xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID" -fixture -login -theme light >/dev/null 2>&1 || true; sleep 8; done
for pair in messages:chats chat-menu:chat-tg profile:client payments:summary schedule:schedule home:today voice:chat-voice-rec; do
  name=${pair%%:*}; screen=${pair##*:}
  to 20 xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID" -fixture -screen "$screen" -theme light >/dev/null 2>&1 || true
  sleep 5
  to 15 xcrun simctl io "$UDID" screenshot "raw-appstore/$name.png" >/dev/null 2>&1 && echo "ok $name"
  if [ ! -s "raw-appstore/$name.png" ]; then   # повтор, если первый запуск не успел
    to 60 xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID" -fixture -screen "$screen" -theme light >/dev/null 2>&1 || true
    sleep 6
    to 15 xcrun simctl io "$UDID" screenshot "raw-appstore/$name.png" >/dev/null 2>&1 && echo "ok $name (повтор)"
  fi
done
pip3 install --quiet pillow 2>/dev/null || pip3 install --quiet --break-system-packages pillow
python3 tools/appstore.py raw-appstore shots/appstore
