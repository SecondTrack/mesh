#!/bin/sh
# build-tlsprobe.sh — baut tools/dev/tlsprobe für den iPod (ARMv7) nach /tmp/tlsprobe.
set -e
cd "$(dirname "$0")/../.."
if ! xcrun --find clang >/dev/null 2>&1; then export DEVELOPER_DIR=/Library/Developer/CommandLineTools; fi
SDK=${THEOS:-$HOME/theos}/sdks/iPhoneOS7.1.sdk
CFLAGS="-arch armv7 -isysroot $SDK -miphoneos-version-min=6.0 -Os"
OBJ=$(mktemp -d)
# Mit ARC übersetzen, ohne -fobjc-arc linken (sonst verlangt clang libarclite, die die CLT nicht haben).
for f in tools/dev/tlsprobe.m mesh/Transport/MeshTLS.m mesh/Transport/MeshWebSocket.m mesh/Transport/MeshTor.m \
         mesh/Transport/MeshCertTime.m mesh/Support/MeshBase64.m mesh/Support/MeshNotifications.m mesh/Crypto/MeshCrypto.m \
         mesh/Compat/MeshCompat.m mesh/Compat/MeshJSON.m mesh/Compat/MeshJSONCodec.m; do
  clang $CFLAGS -fobjc-arc -include mesh/Compat/MeshCompat.h -Imesh/Compat -Imesh/Transport -Imesh/Support -Imesh/Crypto \
        -Ivendor/mbedtls/include -DMESH_USE_TOR=0 -DMESH_BUILD_TIME=$(date +%s) -c "$f" -o "$OBJ/$(basename "$f" .m).o"
done
clang $CFLAGS "$OBJ"/*.o -Lvendor/mbedtls/lib -lmbedtls -lmbedx509 -lmbedcrypto \
      -framework Foundation -framework UIKit -framework Security -o /tmp/tlsprobe
rm -rf "$OBJ"
"${THEOS:-$HOME/theos}/toolchain/linux/iphone/bin/ldid" -S /tmp/tlsprobe 2>/dev/null || ldid -S /tmp/tlsprobe
echo "gebaut: /tmp/tlsprobe"
