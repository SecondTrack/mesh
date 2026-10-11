# Theos-Makefile — baut Mesh als iOS-App (.app im .deb) für iPod touch 3G/4G (iOS 5.0–6.1, ARMv7).
# Voraussetzung: THEOS gesetzt + iOS-7.1-SDK unter $(THEOS)/sdks/iPhoneOS7.1.sdk.
#
# Gevendorte C-Libs (per vendor/… , siehe vendor/README.md):
#   secp256k1  -> Schnorr/BIP-340 + ECDH (Module schnorrsig, extrakeys, ecdh)
#   mbedTLS    -> TLS 1.2/1.3 (mbedtls, mbedx509, mbedcrypto), da iOS-6-System-TLS zu alt ist
#   sqlite3    -> System-Lib (kein Vendoring nötig)
#   CommonCrypto/Security -> System (AES/SHA/Zufall)

# Gegen das iOS-7.1-SDK bauen, Deployment-Target iOS 5.0 → ein Paket für iPod touch 3G (5.1.1)
# und 4G (6.1.6). Was es erst ab iOS 5/6 gibt, kapselt mesh/Compat. Der touch 2G (iOS 4.2.1,
# ARMv6) braucht eine eigene Toolchain, siehe docs/PORTING.md.
TARGET = iphone:clang:7.1:5.0
ARCHS  = armv7
VENDOR_LIB = lib

# iPod touch 2G: make package MESH_DEVICE=2g — braucht das iOS-5.1-SDK mit ARMv6 und libarclite
# sowie alle Bibliotheken für ARMv6 unter vendor/*/lib-armv6 (docs/PORTING.md).
ifeq ($(MESH_DEVICE),2g)
TARGET = iphone:clang:5.1:4.2
ARCHS  = armv6
VENDOR_LIB = lib-armv6
MESH_TOR = 0   # mesh-tor gibt es nur für ARMv7
endif

# Standard ist das Paket zum Weitergeben. Debug-Pakete (make package FINALPACKAGE=0) schreiben
# Documents/mesh.log mit Zeitpunkten und Größen aller Relay-Nachrichten und gehören nur auf Testgeräte.
FINALPACKAGE ?= 1

include $(THEOS)/makefiles/common.mk

ifeq ($(FINALPACKAGE)$(MAKELEVEL),00)
$(info Hinweis: Debug-Build mit Diagnose-Log — nicht weitergeben)
endif

APPLICATION_NAME = Mesh

# Quellen: alle .m unter mesh/ (Schichten siehe docs/ARCHITECTURE.md).
MESH_DIRS   := $(shell find mesh -type d)
Mesh_FILES  = $(shell find mesh -name '*.m' | sort)

# Frameworks (QuartzCore = layer; AVFoundation/CoreMedia/CoreVideo = QR-Kamera-Scan und Videos;
# MediaPlayer = empfangene Videos; CFNetwork = VoIP-Markierung der Sockets).
Mesh_FRAMEWORKS = UIKit CoreGraphics Foundation Security QuartzCore AVFoundation CoreMedia CoreVideo AudioToolbox Accelerate \
                  MediaPlayer CFNetwork CoreText

# ARC + Header-Suchpfade (eigene Schichten + gevendorte Lib-Header).
Mesh_CFLAGS  = -fobjc-arc -O2 -Wall
Mesh_CFLAGS += $(addprefix -I,$(MESH_DIRS))
# Kompatibilitätsschicht in jeder Übersetzungseinheit (iOS-4/5/6-Weichen, siehe mesh/Compat).
Mesh_CFLAGS += -include mesh/Compat/MeshCompat.h
Mesh_CFLAGS += -Ivendor/secp256k1/include -Ivendor/mbedtls/include
Mesh_CFLAGS += -Ivendor/qrcodegen/include -Ivendor/quirc/include

# Tor: eigenes Programm vendor/tor/mesh-tor (tools/build-tor.sh), läuft als LaunchDaemon
# de.mesh.tor (layout/). Die App verbindet dann nur über Tor. MESH_TOR=0 baut ohne.
MESH_TOR ?= 1
Mesh_CFLAGS += -DMESH_USE_TOR=$(MESH_TOR)
# Untergrenze für plausible Geräteuhr (Zertifikats-Ablaufprüfung, siehe MeshCertTime).
Mesh_CFLAGS += -DMESH_BUILD_TIME=$(shell date +%s)

# Linken: gevendorte statische Libs + System-sqlite3.
Mesh_LDFLAGS  = $(foreach v,secp256k1 mbedtls qrcodegen quirc,-Lvendor/$(v)/$(VENDOR_LIB))
Mesh_LIBRARIES = secp256k1 mbedtls mbedx509 mbedcrypto qrcodegen quirc sqlite3

# Entitlements: ohne application-identifier/keychain-access-groups verweigert iOS den Schlüsselbund
# (errSecInteractionNotAllowed), den MeshDeviceSecret für die Gerätebindung des Vaults braucht.
Mesh_CODESIGN_FLAGS = -S$(THEOS_PROJECT_DIR)/ent.plist

include $(THEOS_MAKE_PATH)/application.mk

ifeq ($(MESH_DEVICE),2g)
# Der 2G meldet nur armv6 und iOS 4.2.1 — sonst verweigert SpringBoard die App.
before-package::
	plutil -replace MinimumOSVersion -string 4.2 $(THEOS_STAGING_DIR)/Applications/Mesh.app/Info.plist
	plutil -replace UIRequiredDeviceCapabilities -json '["armv6"]' $(THEOS_STAGING_DIR)/Applications/Mesh.app/Info.plist
endif

# Tor-Programm ins App-Bundle (vom LaunchDaemon gestartet); ohne Tor auch den Dienst weglassen.
before-package::
ifeq ($(MESH_TOR),1)
	install -m 755 vendor/tor/mesh-tor $(THEOS_STAGING_DIR)/Applications/Mesh.app/mesh-tor
else
	rm -f $(THEOS_STAGING_DIR)/Library/LaunchDaemons/de.mesh.tor.plist
endif
