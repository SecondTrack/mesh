#!/bin/sh
# build-mbedtls.sh — mbedTLS aus einem geprüften Release-Archiv für iOS übersetzen.
# Ruft nur clang/ar auf; Makefile und Skripte von mbedTLS werden nicht ausgeführt.
#
#   tools/build-mbedtls.sh <entpacktes mbedtls-3.6.x> [arch]     (arch: armv7, Standard)
#
# Ergebnis: vendor/mbedtls/include und vendor/mbedtls/lib (armv7) bzw. lib-armv6. Einzige Abweichung von der Standardkonfiguration:
# MBEDTLS_HAVE_TIME(_DATE) aus — alte iPods verlieren bei leerem Akku die Uhrzeit; die
# Gültigkeitsprüfung der Zertifikate übernimmt mesh/Transport/MeshCertTime.
set -e
SRC=${1:?Pfad zum entpackten mbedtls-Release}
ARCH=${2:-armv7}
MIN=${MIN_IOS:-$([ "$ARCH" = armv6 ] && echo 4.2 || echo 5.0)}
cd "$(dirname "$0")/.."
OUT=vendor/mbedtls
SDK=${THEOS:-$HOME/theos}/sdks/iPhoneOS7.1.sdk
if ! xcrun --find clang >/dev/null 2>&1; then export DEVELOPER_DIR=/Library/Developer/CommandLineTools; fi

BUILD=$(mktemp -d)
cp -R "$SRC/include" "$BUILD/include"
CFG="$BUILD/include/mbedtls/mbedtls_config.h"
sed -i '' -e 's|^#define MBEDTLS_HAVE_TIME$|//#define MBEDTLS_HAVE_TIME|' \
          -e 's|^#define MBEDTLS_HAVE_TIME_DATE$|//#define MBEDTLS_HAVE_TIME_DATE|' "$CFG"
grep -q '^//#define MBEDTLS_HAVE_TIME$' "$CFG" && grep -q '^//#define MBEDTLS_HAVE_TIME_DATE$' "$CFG"

CFLAGS="-arch $ARCH -isysroot $SDK -miphoneos-version-min=$MIN -Os -fPIC -I$BUILD/include -I$SRC/library"
mkdir -p "$BUILD/obj"
for f in "$SRC"/library/*.c; do
  clang $CFLAGS -c "$f" -o "$BUILD/obj/$(basename "$f" .c).o"
done

# Aufteilung wie upstream: TLS = ssl_*, mps_*, debug, net_sockets; X.509 = x509*, pkcs7; Rest = Krypto.
cd "$BUILD/obj"
TLS=$(ls ssl_*.o mps_*.o debug.o net_sockets.o)
X509=$(ls x509*.o pkcs7.o)
CRYPTO=$(ls *.o | grep -v -x -F "$(printf '%s\n' $TLS $X509)")
cd - >/dev/null
LIBDIR=$OUT/lib; [ "$ARCH" = armv6 ] && LIBDIR=$OUT/lib-armv6
rm -rf "$OUT/include" && mkdir -p "$LIBDIR" && cp -R "$BUILD/include" "$OUT/include"
rm -f "$LIBDIR"/*.a
(cd "$BUILD/obj" && ar rcs libmbedtls.a $TLS && ar rcs libmbedx509.a $X509 && ar rcs libmbedcrypto.a $CRYPTO)
cp "$BUILD"/obj/*.a "$LIBDIR/"
rm -rf "$BUILD"
echo "mbedTLS $(grep 'define MBEDTLS_VERSION_STRING ' $OUT/include/mbedtls/build_info.h | cut -d'"' -f2) für $ARCH (ab iOS $MIN) → $LIBDIR"
