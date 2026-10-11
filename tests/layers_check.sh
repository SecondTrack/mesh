#!/bin/sh
# Prüft die Abhängigkeitstabelle aus docs/ARCHITECTURE.md an den #imports.
cd "$(dirname "$0")/.."
allowed() {   # erlaubte Ziel-Ordner je Schicht (die eigene Schicht ist immer erlaubt)
  case $1 in
    App)       echo "UI Domain Support" ;;
    UI)        echo "Domain Media Model Compat Support" ;;
    Domain)    echo "Transport Storage Protocol Model Crypto Compat Support" ;;
    Media)     echo "Support" ;;
    Transport) echo "Protocol Crypto Compat Support" ;;
    Storage)   echo "Model Crypto Support" ;;
    Protocol)  echo "Crypto Support" ;;
    Model)     echo "Support" ;;
    Crypto)    echo "Support" ;;
    Compat)    echo "Support" ;;
    Support)   echo "" ;;
  esac
}
# Header-Name → Schicht
T=${TMPDIR:-/tmp}/mesh-layers; mkdir -p "$T"
find mesh -name '*.h' | while read h; do echo "$(basename "$h") $(echo "$h" | cut -d/ -f2)"; done > "$T/map"
bad=0
for f in $(find mesh -name '*.[hm]'); do
  layer=$(echo "$f" | cut -d/ -f2)
  ok="$layer $(allowed "$layer")"
  for inc in $(grep -hoE '^#import "[^"]+"' "$f" | cut -d'"' -f2); do
    target=$(awk -v h="$inc" '$1 == h { print $2 }' "$T/map")
    [ -z "$target" ] && continue                      # Vendor-Header
    case " $ok " in *" $target "*) ;; *) echo "FAIL $f ($layer) importiert $inc ($target)"; bad=1 ;; esac
  done
done
# Header mit eingeschränktem Kreis: sqlite-Zugang nur im Store, Schlüsselmaterial nur im Vault
restricted() {   # <Header> <erlaubte Dateien …>
  h=$1; shift
  for f in $(grep -rl "^#import \"$h\"" mesh); do
    case " $* " in *" $f "*) ;; *) echo "FAIL $f importiert $h"; bad=1 ;; esac
  done
}
restricted MeshStore+Internal.h mesh/Storage/MeshStore.m mesh/Storage/MeshStore+Vault.m mesh/Storage/MeshStore+Outbox.m mesh/Storage/MeshStore+Migration.m mesh/Storage/MeshStore+Chat.m mesh/Storage/MeshStore+Signal.m
restricted MeshStore+Vault.h mesh/Storage/MeshStore+Vault.m mesh/Domain/MeshVault.m

[ $bad = 0 ] && echo "ok  Schichtgrenzen eingehalten"
exit $bad
