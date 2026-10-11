#!/bin/sh
# selftest.sh — baut & startet den nativen Krypto-/Protokoll-Test auf dem Mac (kein iOS-SDK nötig).
# Tier 2 (secp256k1) wird automatisch aktiviert, wenn brew's secp256k1 gefunden wird.
set -e
# Altes Xcode im Pfad (nur i386/x86_64) -> auf die Command Line Tools ausweichen.
if ! xcrun --find clang >/dev/null 2>&1 && [ -d /Library/Developer/CommandLineTools ]; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi
cd "$(dirname "$0")/.."

SRC="tools/selftest.m mesh/Crypto/MeshHex.m mesh/Protocol/MeshBech32.m mesh/Crypto/MeshCrypto.m mesh/Support/MeshMemory.m mesh/Support/MeshBase64.m"
INC="-Imesh/Crypto -Imesh/Protocol -Imesh/Support"
FLAGS="-fobjc-arc -framework Foundation -framework Security"
OUT="/tmp/mesh-selftest"

# secp256k1 via Homebrew? -> Tier 2 dazu.
if PREFIX=$(brew --prefix secp256k1 2>/dev/null) && [ -f "$PREFIX/include/secp256k1_schnorrsig.h" ]; then
  echo "secp256k1 gefunden unter $PREFIX -> Tier 2 aktiv"
  SRC="$SRC mesh/Protocol/MeshKeys.m mesh/Protocol/MeshEvent.m mesh/Support/MeshTime.m mesh/Protocol/MeshNip04.m"
  INC="$INC -I$PREFIX/include"
  FLAGS="$FLAGS -DMESH_HAVE_SECP -L$PREFIX/lib -lsecp256k1"
else
  echo "secp256k1 nicht gefunden -> nur Tier 1 (brew install secp256k1 für Tier 2)"
fi

clang $SRC $INC $FLAGS -o "$OUT"
exec "$OUT"
