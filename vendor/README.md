# vendor/ — gevendorte C-Bibliotheken (ARMv7, iOS 6)

Zwei Libs müssen für **ARMv7** cross-kompiliert und ins App-Binary gelinkt werden. Beide sind reines
C und lassen sich mit dem iOS-6-SDK-Clang bauen.

Erwartete Struktur (vom Makefile referenziert):

```
vendor/
├── secp256k1/
│   ├── include/            secp256k1.h, secp256k1_schnorrsig.h, secp256k1_extrakeys.h, secp256k1_ecdh.h
│   └── lib/libsecp256k1.a
└── mbedtls/
    ├── include/mbedtls/    *.h
    └── lib/{libmbedtls.a, libmbedx509.a, libmbedcrypto.a}
```

## secp256k1 (Schnorr/BIP-340 + ECDH)

Aus https://github.com/bitcoin-core/secp256k1 — **mit** den Modulen schnorrsig, extrakeys, ecdh:

```sh
SDK=$(xcrun --sdk iphoneos --show-sdk-path)   # bzw. der iOS-6-SDK-Pfad aus Theos
CC="$(xcrun -f clang) -arch armv7 -isysroot $SDK -miphoneos-version-min=6.0"
./autogen.sh
./configure --host=arm-apple-darwin CC="$CC" \
  --enable-module-schnorrsig --enable-module-extrakeys --enable-module-ecdh \
  --enable-static --disable-shared --disable-tests --disable-benchmark
make
# -> .libs/libsecp256k1.a  nach vendor/secp256k1/lib/
# -> include/*.h            nach vendor/secp256k1/include/
```

## mbedTLS (TLS 1.2/1.3 — ersetzt den toten iOS-6-System-TLS)

Version **3.6.7** (LTS). Release-Archiv laden und die SHA256-Summe mit der Angabe auf der
Release-Seite vergleichen, dann mit unserem eigenen Skript übersetzen (ruft nur clang/ar auf,
nicht das mbedTLS-Build-System):

```sh
curl -LO https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-3.6.7/mbedtls-3.6.7.tar.bz2
shasum -a 256 mbedtls-3.6.7.tar.bz2   # a7e8bcbec0e6f761b4af24f25677626b35f762f68eef79c08677a363212d11f6
tar xjf mbedtls-3.6.7.tar.bz2
tools/build-mbedtls.sh mbedtls-3.6.7 armv7     # armv6 für den iPod touch 2G
```

Einzige Abweichung von der Standardkonfiguration: `MBEDTLS_HAVE_TIME(_DATE)` aus (siehe Skript).
Am Gerät prüfen: `tools/dev/build-tlsprobe.sh`, dann `/tmp/tlsprobe` mit `cacert.pem` daneben
per SSH ausführen.

## tor (vendor/tor/mesh-tor)

Tor 0.4.9.14 mit OpenSSL 3.5.9 und libevent 2.1.13, als eigenes Programm für ARMv7 (iOS 5+):
`tools/build-tor.sh <ordner mit den drei Archiven>` (Prüfsummen und Signaturschlüssel im Skript).
Läuft als LaunchDaemon `de.mesh.tor` oder, wenn der nicht geladen ist, von der App gestartet in
eigener Prozessgruppe; SOCKS nur auf 127.0.0.1:19050, Steuerung als Unix-Socket im Datenordner (Cookie), `ClientOnly 1`.
Am iPod 4G: erster Start ~80 s (Verzeichnis ~35 MB auf der Platte), danach sofort bereit.
Lizenzen: Tor 3-Klausel-BSD, OpenSSL Apache 2.0, libevent 3-Klausel-BSD.

## Emojis (Resources/emoji.pack, emoji.idx)

Noto Emoji von Google, Tag `v2026-09-24-unicode18_0`, Bilder aus `2D/png/72` auf 40 px verkleinert
und gepackt: `tools/build-emoji.sh <ordner>`. Bilder Apache 2.0, Schrift SIL OFL 1.1 (laut README
des Projekts). Siehe mesh/UI/Common/MeshEmoji.h.

## Wortlisten (Resources/wordlist-*.txt)

de-7776 von dys2p (CC0); EFF Large Wordlist (Electronic Frontier Foundation, CC BY 3.0), geändert:
Bindestriche entfernt, yo-yo durch yolk ersetzt (siehe mesh/Domain/MeshPassphrase.h).

## Ohne Gerät testen

Die Krypto-/Protokoll-Logik (Hex, Bech32, SHA/AES, Event-ID/NIP-01, Schnorr, NIP-04) ist SDK-unabhängig
und läuft **nativ auf dem Mac**: `tools/selftest.sh` (baut gegen macOS-Foundation, secp256k1 optional via brew).
Das ist der schnellste Korrektheits-Check, bevor überhaupt ein .deb aufs Gerät geht.
