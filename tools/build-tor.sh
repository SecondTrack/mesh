#!/bin/sh
# build-tor.sh — Tor als eigenes Programm für den iPod (armv7, iOS 5+) übersetzen: OpenSSL,
# libevent und Tor aus geprüften Release-Archiven. Hier laufen deren configure/make; das Ergebnis
# läuft nur auf dem iPod (als LaunchDaemon de.mesh.tor, siehe layout/).
#
#   tools/build-tor.sh <ordner mit den drei Archiven>
#
# Vorher die Signaturen prüfen (gpg --verify): Tor über tor-*.sha256sum.asc (David Goulet,
# B74417EDDF22AC9F9E90F49142E86A2A11F48D36), OpenSSL (openssl@openssl.org,
# C46ED3F2CBEFDA1FDAADA44264ED7B1DCCE71CB2), libevent (Nick Mathewson, 7A02B3521DC75C542BA015456AFEE6D49E92B601).
# Die Prüfsummen unten müssen passen, sonst bricht das Skript ab.
#
# Abweichungen für iOS 5/6: OpenSSL ohne Assembler (der ARM-Code lässt sich mit aktuellem clang
# nicht mehr assemblieren) und mit BROKEN_CLANG_ATOMICS (64-Bit-Atomics fehlen der armv7-Laufzeit,
# OpenSSL nimmt dann Sperren); Tor ohne _NSGetEnviron/memset_s (fehlen im iOS-6-libSystem).
# Ergebnis: vendor/tor/mesh-tor (mit ldid signiert).
set -e
SRC=${1:?Ordner mit tor-, openssl- und libevent-Archiv}
TOR=tor-0.4.9.14 OSSL=openssl-3.5.9 EVENT=libevent-2.1.13-stable
cd "$(dirname "$0")/.."
ROOT=$PWD
check() { [ "$(shasum -a 256 "$SRC/$1" | cut -d' ' -f1)" = "$2" ] || { echo "Prüfsumme falsch: $1" >&2; exit 1; }; }
check $TOR.tar.gz   182449ac1c8ff43278da27b69b02040e11d03d0327db6d9126e4190ec6235e4a
check $OSSL.tar.gz  603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a
check $EVENT.tar.gz f7e9383b8c0baa81b687e5b5eecc01beefaf1b19b64151d95ed61647fe7a315c

export DEVELOPER_DIR=/Library/Developer/CommandLineTools
SDK=${THEOS:-$HOME/theos}/sdks/iPhoneOS7.1.sdk
B=$(mktemp -d)
trap 'rm -rf "$B"' EXIT
cd "$B"
for a in $TOR $OSSL $EVENT; do tar xzf "$SRC/$a.tar.gz"; done
CC1="clang -arch armv7 -isysroot $SDK -miphoneos-version-min=5.0"

(cd $OSSL && ./Configure ios-xcrun no-asm no-shared no-tests no-apps no-docs no-engine no-dso no-quic no-ui-console no-comp \
   --prefix="$B/out/openssl" CC="clang -isysroot $SDK -miphoneos-version-min=5.0" -Os -DBROKEN_CLANG_ATOMICS \
   && make -j8 build_libs && make install_dev)
(cd $EVENT && CC="$CC1" CFLAGS=-Os ./configure --host=arm-apple-darwin --prefix="$B/out/libevent" --disable-shared \
   --enable-static --disable-openssl --disable-samples --disable-libevent-regress --disable-debug-mode --disable-clock-gettime \
   && make -j8 && make install)
(cd $TOR && CC="$CC1" CFLAGS=-Os ./configure --host=arm-apple-darwin ac_cv_func__NSGetEnviron=no ac_cv_func_memset_s=no \
   --disable-asciidoc --disable-manpage --disable-html-manual --disable-unittests --disable-system-torrc \
   --disable-module-relay --disable-module-dirauth --disable-seccomp --disable-libscrypt --disable-zstd --disable-lzma \
   --disable-tool-name-check --disable-gcc-hardening --disable-linker-hardening \
   --enable-static-libevent --with-libevent-dir="$B/out/libevent" --enable-static-openssl --with-openssl-dir="$B/out/openssl" \
   && make -j8 libtor.a)

printf '#include "tor_api.h"\nint main(int argc, char **argv) { return tor_main(argc, argv); }\n' > main.c
$CC1 -Os -I$TOR/src/feature/api main.c $TOR/libtor.a out/libevent/lib/libevent.a out/openssl/lib/libssl.a \
     out/openssl/lib/libcrypto.a -lz -lm -o mesh-tor
strip -x mesh-tor
mkdir -p "$ROOT/vendor/tor"
cp mesh-tor "$ROOT/vendor/tor/mesh-tor"
ldid -S "$ROOT/vendor/tor/mesh-tor"
rm -rf "$B"
echo "gebaut: vendor/tor/mesh-tor"
