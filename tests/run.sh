#!/bin/sh
# Alle Mac-Tests. Jede Suite wird gebaut und ausgeführt; am Ende eine Übersicht.
# Exit-Code 0 nur, wenn jede Suite gebaut wurde und bestanden hat.
if ! xcrun --find clang >/dev/null 2>&1 && [ -d /Library/Developer/CommandLineTools ]; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi
cd "$(dirname "$0")/.."
OUT=$(mktemp -d "${TMPDIR:-/tmp}/mesh-tests.XXXXXX")   # eigenes Verzeichnis: parallele Läufe stören sich nicht
trap 'rm -rf "$OUT"' EXIT
FAILED=""
BASE="-fobjc-arc -framework Foundation -Wno-deprecated-declarations -Itests"

# suite <Name> <Testdatei> <Flags und Quellen …>
suite() {
  name=$1; test=$2; shift 2
  echo "-- $name"
  bin="$OUT/$(basename "$test" .m)"
  if ! clang $BASE "$@" -o "$bin" "$test"; then FAILED="$FAILED\n  $name (Build)"; return; fi
  "$bin" || FAILED="$FAILED\n  $name"
}

echo "-- Krypto/Protokoll (tools/selftest.sh)"
sh tools/selftest.sh | tail -1 | tee "$OUT/selftest.log"
grep -q ' 0 fehlgeschlagen' "$OUT/selftest.log" || FAILED="$FAILED\n  Krypto/Protokoll"

suite JSON              tests/json_test.m      -Imesh/Compat mesh/Compat/MeshJSONCodec.m
suite PBKDF2            tests/crypto_test.m    -framework Security -Imesh/Crypto -Imesh/Support mesh/Crypto/MeshCrypto.m mesh/Support/MeshMemory.m mesh/Crypto/MeshHex.m
suite Absender-Folgen   tests/runs_test.m      -Imesh/Model -Imesh/Support mesh/Model/MeshMessage.m mesh/Model/MeshPayload.m mesh/Support/MeshBase64.m
suite Base64            tests/base64_test.m    -Imesh/Support mesh/Support/MeshBase64.m
suite Nachrichtenformat tests/payload_test.m   -Imesh/Model -Imesh/Support mesh/Model/MeshPayload.m mesh/Support/MeshBase64.m
suite scrypt            tests/scrypt_test.m    -O2 -Imesh/Crypto -Imesh/Support mesh/Crypto/MeshScrypt.m mesh/Crypto/MeshHex.m mesh/Support/MeshMemory.m
suite Passphrase        tests/passphrase_test.m -framework Security -Imesh/Domain -Imesh/Crypto -Imesh/Support mesh/Domain/MeshPassphrase.m \
                        mesh/Crypto/MeshCrypto.m mesh/Support/MeshMemory.m
suite Curve25519        tests/curve_test.m     -Imesh/Crypto -Imesh/Support mesh/Crypto/MeshCurve25519.m mesh/Crypto/MeshHex.m mesh/Support/MeshMemory.m
suite Signal            tests/signal_test.m    -framework Security -Imesh/Domain -Imesh/Protocol -Imesh/Crypto -Imesh/Support \
                        mesh/Domain/MeshSignal.m mesh/Protocol/MeshSignalSession.m mesh/Protocol/MeshSignalWire.m mesh/Protocol/MeshSignalBundle.m \
                        mesh/Crypto/MeshCurve25519.m mesh/Crypto/MeshCrypto.m mesh/Crypto/MeshHex.m mesh/Support/MeshBase64.m mesh/Support/MeshMemory.m
suite Umschlag          tests/envelope_test.m -framework Security -Imesh/Protocol -Imesh/Crypto -Imesh/Support \
                        mesh/Protocol/MeshEnvelope.m mesh/Crypto/MeshCrypto.m mesh/Crypto/MeshHex.m mesh/Support/MeshBase64.m mesh/Support/MeshMemory.m
suite Relay-Pool        tests/pool_test.m      -include tests/fakes/MeshTestPrefix.h -Itests/fakes -Imesh/Transport -Imesh/Support -Imesh/Protocol \
                        tests/fakes/MeshRelayFake.m tests/fakes/MeshEventFake.m mesh/Transport/MeshRelayPool.m mesh/Transport/MeshVerifiedEvents.m mesh/Transport/MeshTor.m mesh/Support/MeshNotifications.m
suite Speicher          tests/store_test.m     -framework Security -Imesh/Storage -Imesh/Model -Imesh/Support -Imesh/Crypto -lsqlite3 \
                        mesh/Storage/MeshStore.m mesh/Support/MeshTime.m mesh/Storage/MeshStore+Migration.m mesh/Storage/MeshStore+Vault.m mesh/Storage/MeshStore+Outbox.m mesh/Storage/MeshStore+Chat.m mesh/Storage/MeshStore+Signal.m mesh/Storage/MeshVaultRecord.m mesh/Model/MeshChat.m mesh/Model/MeshMessage.m mesh/Model/MeshProfile.m mesh/Model/MeshPayload.m mesh/Support/MeshBase64.m \
                        mesh/Crypto/MeshSeal.m mesh/Crypto/MeshCrypto.m mesh/Support/MeshMemory.m mesh/Support/MeshText.m
suite Fremde            tests/inbox_test.m     -Imesh/Domain -framework Security -Imesh/Storage -Imesh/Model -Imesh/Support -Imesh/Crypto -lsqlite3 \
                        mesh/Storage/MeshStore.m mesh/Support/MeshTime.m mesh/Storage/MeshStore+Migration.m mesh/Domain/MeshInboxPolicy.m mesh/Storage/MeshStore+Vault.m mesh/Storage/MeshStore+Outbox.m mesh/Storage/MeshStore+Chat.m mesh/Storage/MeshStore+Signal.m mesh/Storage/MeshVaultRecord.m mesh/Model/MeshChat.m mesh/Model/MeshMessage.m mesh/Model/MeshProfile.m mesh/Model/MeshPayload.m mesh/Support/MeshBase64.m \
                        mesh/Crypto/MeshSeal.m mesh/Crypto/MeshCrypto.m mesh/Support/MeshMemory.m mesh/Support/MeshText.m
suite Versiegeln        tests/seal_test.m      -framework Security -Imesh/Crypto -Imesh/Support mesh/Crypto/MeshSeal.m mesh/Crypto/MeshCrypto.m mesh/Support/MeshMemory.m mesh/Support/MeshBase64.m
suite Audio             tests/audio_test.m     -framework CoreGraphics -framework AudioToolbox -framework Accelerate -Imesh/Media -Imesh/Support \
                        mesh/Media/MeshAudioCodec.m mesh/Media/MeshAudioDSP.m mesh/Media/MeshVoiceFX.m mesh/Media/MeshPcmBuffer.m mesh/Media/MeshMediaCheck.m mesh/Support/MeshLog.m mesh/Support/MeshMemory.m
suite Medienprüfung     tests/mediacheck_test.m -framework CoreGraphics -framework ImageIO -framework CoreServices -Imesh/Media mesh/Media/MeshMediaCheck.m
suite Zertifikatszeit   tests/certtime_test.m  -Imesh/Transport mesh/Transport/MeshCertTime.m
suite WebSocket         tests/websocket_test.m -framework Security -Itests/fakes -Imesh/Transport -Imesh/Support -Imesh/Crypto \
                        tests/fakes/MeshTLSFake.m mesh/Transport/MeshWebSocket.m mesh/Support/MeshBase64.m mesh/Crypto/MeshCrypto.m mesh/Support/MeshMemory.m
suite Kontakt-Code      tests/contactcode_test.m -Imesh/Protocol -Imesh/Crypto mesh/Protocol/MeshContactCode.m mesh/Protocol/MeshBech32.m mesh/Crypto/MeshHex.m
suite Bech32            tests/bech32_test.m    -Imesh/Protocol -Imesh/Crypto mesh/Protocol/MeshBech32.m mesh/Crypto/MeshHex.m
suite Text              tests/text_test.m      -Imesh/Support mesh/Support/MeshText.m
suite Sicherheitscode    tests/safetycode_test.m -Imesh/Protocol mesh/Protocol/MeshSafetyCode.m
suite Tastatur         tests/keyboard_test.m  -framework CoreGraphics -Imesh/UI/Common mesh/UI/Common/MeshKeyboardLayout.m mesh/UI/Common/MeshCustomEmoji.m
suite Chat-Eingabe     tests/linetext_test.m  -framework CoreGraphics -Imesh/UI/Common -Imesh/Support mesh/UI/Common/MeshLineText.m \
                        mesh/UI/Common/MeshKeyboardLayout.m mesh/UI/Common/MeshCustomEmoji.m mesh/Support/MeshText.m
suite Emojis           tests/emoji_test.m     -framework CoreText -framework CoreGraphics -Imesh/UI/Common mesh/UI/Common/MeshEmojiText.m mesh/UI/Common/MeshCustomEmoji.m
suite Netzstatus        tests/connect_test.m   -framework SystemConfiguration -Imesh/UI/Lock -Imesh/Transport -Imesh/Support \
                        mesh/UI/Lock/MeshConnectPolicy.m mesh/Transport/MeshReachability.m mesh/Support/MeshNotifications.m
suite PIN-Sperre        tests/pinguard_test.m  -Imesh/Domain mesh/Domain/MeshPinGuard.m
suite Gruppen-Speicher  tests/groups_store_test.m -framework Security -Imesh/Storage -Imesh/Model -Imesh/Support -Imesh/Crypto -lsqlite3 \
                        mesh/Storage/MeshStore.m mesh/Support/MeshTime.m mesh/Storage/MeshStore+Migration.m mesh/Storage/MeshStore+Vault.m mesh/Storage/MeshStore+Outbox.m mesh/Storage/MeshStore+Chat.m mesh/Storage/MeshStore+Signal.m mesh/Storage/MeshStore+Group.m mesh/Storage/MeshVaultRecord.m mesh/Model/MeshChat.m mesh/Model/MeshMessage.m mesh/Model/MeshProfile.m mesh/Model/MeshPayload.m mesh/Support/MeshBase64.m \
                        mesh/Crypto/MeshSeal.m mesh/Crypto/MeshCrypto.m mesh/Support/MeshMemory.m mesh/Support/MeshText.m
suite Notlöschung       tests/panic_test.m     -framework Security -Imesh/Domain -Imesh/Crypto -Imesh/Support mesh/Domain/MeshPanic.m mesh/Support/MeshTime.m \
                        mesh/Domain/MeshKeychain.m mesh/Crypto/MeshCrypto.m mesh/Crypto/MeshHex.m mesh/Support/MeshMemory.m mesh/Support/MeshLog.m

echo "-- Texte"
sh tests/strings_check.sh || FAILED="$FAILED\n  Texte"

echo "-- Schichten"
sh tests/layers_check.sh || FAILED="$FAILED\n  Schichten"

if PREFIX=$(brew --prefix secp256k1 2>/dev/null) && [ -f "$PREFIX/include/secp256k1_schnorrsig.h" ]; then
  SECP="-framework Security -I$PREFIX/include -L$PREFIX/lib -lsecp256k1 -DMESH_HAVE_SECP"
  suite Vault           tests/vault_test.m $SECP -Imesh/Crypto -Imesh/Protocol -Imesh/Storage -Imesh/Domain -Imesh/Model -Imesh/Support -lsqlite3 \
                        mesh/Domain/MeshVault.m mesh/Crypto/MeshScrypt.m mesh/Storage/MeshStore.m mesh/Support/MeshTime.m mesh/Storage/MeshStore+Migration.m mesh/Storage/MeshStore+Vault.m mesh/Storage/MeshStore+Outbox.m mesh/Storage/MeshStore+Chat.m mesh/Storage/MeshStore+Signal.m mesh/Storage/MeshVaultRecord.m mesh/Protocol/MeshKeys.m mesh/Crypto/MeshCrypto.m mesh/Support/MeshMemory.m mesh/Crypto/MeshHex.m mesh/Crypto/MeshSeal.m \
                        mesh/Model/MeshChat.m mesh/Model/MeshMessage.m mesh/Model/MeshProfile.m mesh/Model/MeshPayload.m mesh/Support/MeshBase64.m mesh/Support/MeshLog.m mesh/Support/MeshText.m
  suite NIP-44          tests/nip44_test.m $SECP -Imesh/Protocol -Imesh/Crypto -Imesh/Support \
                        mesh/Protocol/MeshNip44.m mesh/Protocol/MeshKeys.m mesh/Crypto/MeshChaCha20.m mesh/Crypto/MeshCrypto.m \
                        mesh/Crypto/MeshHex.m mesh/Support/MeshMemory.m mesh/Support/MeshBase64.m
  suite Nachrichten     tests/messenger_test.m $SECP -include tests/fakes/MeshTestPrefix.h -lsqlite3 -Imesh/Domain -Imesh/Storage -Imesh/Model \
                        -Imesh/Protocol -Imesh/Crypto -Imesh/Support -Imesh/Compat mesh/Domain/MeshMessenger.m mesh/Domain/MeshMessenger+Groups.m mesh/Domain/MeshMessenger+GroupsOpen.m mesh/Protocol/MeshGroupLink.m \
                        mesh/Storage/MeshStore+Group.m mesh/Protocol/MeshGroupState.m mesh/Compat/MeshJSON.m mesh/Compat/MeshJSONCodec.m mesh/Domain/MeshInboxPolicy.m \
                        mesh/Domain/MeshPanic.m mesh/Domain/MeshKeychain.m mesh/Support/MeshLog.m mesh/Domain/MeshSignal.m \
                        mesh/Protocol/MeshSignalSession.m mesh/Protocol/MeshSignalWire.m mesh/Protocol/MeshSignalBundle.m mesh/Crypto/MeshCurve25519.m \
                        mesh/Storage/MeshStore.m mesh/Support/MeshTime.m mesh/Storage/MeshStore+Migration.m mesh/Storage/MeshStore+Vault.m mesh/Storage/MeshStore+Outbox.m \
                        mesh/Storage/MeshStore+Chat.m mesh/Storage/MeshStore+Signal.m mesh/Storage/MeshVaultRecord.m mesh/Model/MeshChat.m mesh/Model/MeshMessage.m \
                        mesh/Model/MeshProfile.m mesh/Model/MeshPayload.m mesh/Protocol/MeshEnvelope.m mesh/Protocol/MeshNip04.m \
                        mesh/Protocol/MeshNip44.m mesh/Protocol/MeshKeys.m mesh/Protocol/MeshEvent.m mesh/Crypto/MeshChaCha20.m \
                        mesh/Crypto/MeshCrypto.m mesh/Crypto/MeshHex.m mesh/Crypto/MeshSeal.m mesh/Support/MeshMemory.m \
                        mesh/Support/MeshBase64.m mesh/Support/MeshText.m
  suite Gruppen        tests/groups_test.m $SECP -include tests/fakes/MeshTestPrefix.h -lsqlite3 -Itests/fakes -Imesh/Domain -Imesh/Storage -Imesh/Model \
                        -Imesh/Protocol -Imesh/Crypto -Imesh/Support -Imesh/Compat -Imesh/Transport mesh/Domain/MeshMessenger.m mesh/Domain/MeshMessenger+Groups.m mesh/Domain/MeshMessenger+GroupsOpen.m mesh/Protocol/MeshGroupLink.m \
                        mesh/Domain/MeshTeam.m mesh/Domain/MeshInboxPolicy.m mesh/Domain/MeshPanic.m mesh/Domain/MeshKeychain.m mesh/Support/MeshLog.m mesh/Domain/MeshSignal.m \
                        mesh/Protocol/MeshSignalSession.m mesh/Protocol/MeshSignalWire.m mesh/Protocol/MeshSignalBundle.m mesh/Crypto/MeshCurve25519.m \
                        mesh/Storage/MeshStore.m mesh/Support/MeshTime.m mesh/Storage/MeshStore+Migration.m mesh/Storage/MeshStore+Vault.m mesh/Storage/MeshStore+Outbox.m \
                        mesh/Storage/MeshStore+Chat.m mesh/Storage/MeshStore+Signal.m mesh/Storage/MeshStore+Group.m mesh/Storage/MeshVaultRecord.m mesh/Model/MeshChat.m mesh/Model/MeshMessage.m \
                        mesh/Model/MeshProfile.m mesh/Model/MeshPayload.m mesh/Protocol/MeshEnvelope.m mesh/Protocol/MeshGroupState.m mesh/Protocol/MeshTeamPost.m mesh/Protocol/MeshNip04.m \
                        mesh/Protocol/MeshNip44.m mesh/Protocol/MeshKeys.m mesh/Protocol/MeshEvent.m mesh/Crypto/MeshChaCha20.m \
                        mesh/Crypto/MeshCrypto.m mesh/Crypto/MeshHex.m mesh/Crypto/MeshSeal.m mesh/Support/MeshMemory.m \
                        mesh/Support/MeshBase64.m mesh/Support/MeshText.m mesh/Compat/MeshJSON.m mesh/Compat/MeshJSONCodec.m \
                        mesh/Transport/MeshRelayPool.m mesh/Transport/MeshVerifiedEvents.m mesh/Transport/MeshTor.m tests/fakes/MeshRelayFake.m mesh/Support/MeshNotifications.m
  suite Wächter         tests/watcher_test.m $SECP -include tests/fakes/MeshTestPrefix.h -Itests/fakes -Imesh/Domain -Imesh/Transport \
                        -Imesh/Protocol -Imesh/Crypto -Imesh/Support mesh/Domain/MeshInboxWatcher.m mesh/Domain/MeshPanic.m \
                        mesh/Domain/MeshKeychain.m mesh/Transport/MeshRelayPool.m mesh/Transport/MeshVerifiedEvents.m tests/fakes/MeshRelayFake.m mesh/Transport/MeshTor.m \
                        mesh/Protocol/MeshEvent.m mesh/Support/MeshTime.m mesh/Protocol/MeshKeys.m mesh/Crypto/MeshCrypto.m \
                        mesh/Crypto/MeshHex.m mesh/Support/MeshMemory.m mesh/Support/MeshLog.m mesh/Support/MeshNotifications.m \
                        mesh/Compat/MeshJSON.m mesh/Compat/MeshJSONCodec.m -Imesh/Compat
  suite Events          tests/event_test.m $SECP -include tests/fakes/MeshTestPrefix.h -Itests/fakes -Imesh/Protocol -Imesh/Crypto \
                        -Imesh/Transport -Imesh/Support -Imesh/Compat \
                        mesh/Protocol/MeshEvent.m mesh/Support/MeshTime.m mesh/Protocol/MeshKeys.m mesh/Crypto/MeshCrypto.m mesh/Support/MeshMemory.m mesh/Crypto/MeshHex.m \
                        mesh/Transport/MeshRelay.m mesh/Transport/MeshWebSocket.m tests/fakes/MeshTLSFake.m mesh/Support/MeshBase64.m \
                        mesh/Support/MeshLog.m mesh/Compat/MeshJSON.m mesh/Compat/MeshJSONCodec.m
else
  FAILED="$FAILED\n  Vault/Events (secp256k1 fehlt: brew install secp256k1)"
fi

if [ -n "$FAILED" ]; then printf "\nFEHLGESCHLAGEN:$FAILED\n"; exit 1; fi
echo; echo "Alle Suites bestanden."
