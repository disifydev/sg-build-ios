#!/bin/bash
# Итог снимков: падения, пустые экраны, отчёты о сбоях.
FAIL=0
[ -f shots/FAILED.txt ] && { echo "Упали:"; cat shots/FAILED.txt; FAIL=1; }
for f in shots/*.png; do
  SZ=$(stat -f%z "$f")
  if [ "$SZ" -lt 40000 ]; then echo "ПУСТОЙ ЭКРАН? $f ($SZ байт)"; FAIL=1; fi
done
mkdir -p shots/crashes
find "$HOME/Library/Logs/DiagnosticReports" -name "Sguardo*" -newermt "-2 hour" -exec cp {} shots/crashes/ \; 2>/dev/null || true
for c in shots/crashes/*; do [ -f "$c" ] && { echo "=== $c"; head -120 "$c"; }; done
ls shots | wc -l
exit $FAIL
