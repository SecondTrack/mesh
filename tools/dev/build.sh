#!/bin/sh
# build.sh — baut die Mac-Testwerkzeuge gegen die Mesh-Krypto/-Protokoll-Schicht.
#   nostrbot  simulierte Gegenstelle (Format der Apps, NIP-44/NIP-04, antwortet und steuert)
#   sendtest  schickt eine einzelne DM an einen Pubkey
#   query     fragt das Relay nach eigenem Profil und DMs ab
#   personas  fünf Test-Accounts mit Profil schreiben dem iPod (Design-Check)
#   signalinterop  MeshSignal von der Kommandozeile (Gegenprobe mit libsignal, tools/dev/interop/)
# Voraussetzung: brew install secp256k1
# Aufruf: tools/dev/build.sh [nostrbot|sendtest|query]   (ohne Argument: alle)
set -e
# Altes Xcode im Pfad (nur i386/x86_64) -> auf die Command Line Tools ausweichen.
if ! xcrun --find clang >/dev/null 2>&1 && [ -d /Library/Developer/CommandLineTools ]; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi
cd "$(dirname "$0")/../.."

PREFIX=$(brew --prefix secp256k1 2>/dev/null) || { echo "secp256k1 fehlt: brew install secp256k1" >&2; exit 1; }
CORE="mesh/Crypto/MeshHex.m mesh/Crypto/MeshCrypto.m mesh/Protocol/MeshBech32.m \
      mesh/Protocol/MeshKeys.m mesh/Protocol/MeshEvent.m mesh/Support/MeshTime.m mesh/Protocol/MeshNip04.m mesh/Protocol/MeshNip44.m \
      mesh/Protocol/MeshEnvelope.m mesh/Crypto/MeshChaCha20.m mesh/Support/MeshBase64.m \
      mesh/Support/MeshMemory.m mesh/Model/MeshPayload.m mesh/Media/MeshAudioCodec.m mesh/Support/MeshLog.m"
CORE="$CORE mesh/Domain/MeshSignal.m mesh/Protocol/MeshSignalSession.m mesh/Protocol/MeshSignalWire.m \
      mesh/Protocol/MeshSignalBundle.m mesh/Crypto/MeshCurve25519.m"
INC="-Imesh/Crypto -Imesh/Protocol -Imesh/Support -Imesh/Model -Imesh/Media -Imesh/Domain -Itools/dev -I$PREFIX/include"
FLAGS="-fobjc-arc -framework Foundation -framework Security -framework AudioToolbox -framework CoreImage -framework ImageIO -framework CoreGraphics -DMESH_HAVE_SECP -L$PREFIX/lib -lsecp256k1"
OUT="${OUT:-/tmp}"

for tool in ${1:-nostrbot sendtest query signalinterop personas}; do
  clang $FLAGS $INC -o "$OUT/mesh-$tool" "tools/dev/$tool.m" $CORE
  echo "gebaut: $OUT/mesh-$tool"
done
