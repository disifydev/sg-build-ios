#!/bin/bash
# Снимок экрана демо-режима в светлой и тёмной теме: tools/shot.sh <имя> <аргументы запуска…>
# UDID симулятора — в файле .udid (пишет шаг «Симулятор»). Ошибки не роняют шаг: итог проверяет tools/check.sh.
UDID=$(cat .udid)
BUNDLE_ID=${BUNDLE_ID:-dev.disify.batch}
name=$1; shift
mkdir -p shots
to() { perl -e 'alarm shift; exec @ARGV' "$@"; }   # на macOS нет timeout
for theme in light dark; do
  to 10 xcrun simctl ui "$UDID" appearance "$theme" >/dev/null 2>&1 || true
  t0=$(date +%s)
  to 20 xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID" "$@" -theme "$theme" >/dev/null 2>&1 || echo "  запуск $name-$theme не ответил за 20 с"
  sleep 4
  alive() { to 10 xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | grep -q "UIKitApplication:$BUNDLE_ID"; }
  if alive || { sleep 3; alive; }; then
    to 15 xcrun simctl io "$UDID" screenshot "shots/$name-$theme.png" >/dev/null 2>&1
    echo "ok   $name-$theme ($(( $(date +%s) - t0 )) с)"
  else
    to 15 xcrun simctl io "$UDID" screenshot "shots/$name-$theme-CRASH.png" >/dev/null 2>&1 || true
    echo "FAIL $name-$theme — приложение упало"
    echo "$name-$theme" >> shots/FAILED.txt
  fi
done
exit 0
