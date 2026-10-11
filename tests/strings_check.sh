#!/bin/sh
# Jeder L()/LF()-Schlüssel steht in en und de, und keine Datei hat Leichen.
cd "$(dirname "$0")/.."
T=${TMPDIR:-/tmp}/mesh-strings; mkdir -p "$T"
grep -rhoE 'LF?\(@"([^"\\]|\\.)*"' mesh | sed -E 's/^LF?\(@//' | sort -u > "$T/used"
bad=0
for lang in en de; do
  grep -oE '^"([^"\\]|\\.)*" =' Resources/$lang.lproj/Localizable.strings | sed 's/ =$//' | sort > "$T/$lang.all"
  sort -u "$T/$lang.all" > "$T/$lang"
  dup=$(comm -23 "$T/$lang.all" "$T/$lang" | head -3)
  miss=$(comm -23 "$T/used" "$T/$lang" | head -50)
  dead=$(comm -13 "$T/used" "$T/$lang" | head -50)
  [ -n "$dup" ]  && { echo "FAIL $lang doppelt: $dup"; bad=1; }
  [ -n "$miss" ] && { echo "FAIL $lang fehlt: $miss"; bad=1; }
  [ -n "$dead" ] && { echo "FAIL $lang unbenutzt: $dead"; bad=1; }
done
[ $bad = 0 ] && echo "ok  $(wc -l < "$T/used" | tr -d ' ') Texte in en und de"
exit $bad
