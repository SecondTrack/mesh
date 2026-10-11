# Portierung auf ältere iPods

Eine Codebasis für alle Geräte. Unterschiede zwischen iOS-Versionen stecken in `mesh/Compat`
(siehe ARCHITECTURE.md), Unterschiede in der Hardware in `MeshCaps`.

| Gerät         | iOS   | CPU   | Paket                         | Stand |
|---------------|-------|-------|-------------------------------|-------|
| iPod touch 4G | 6.1.6 | ARMv7 | `make package`                | läuft |
| iPod touch 3G | 5.1.1 | ARMv7 | `make package` (dasselbe)     | gebaut, Gerätetest offen |
| iPod touch 2G | 4.2.1 | ARMv6 | `make package MESH_DEVICE=2g` | Code bereit, Toolchain fehlt |

## touch 3G (iOS 5.1.1)

Das normale Paket läuft ab iOS 5.0 (Deployment-Target und `MinimumOSVersion`). Was sich gegenüber
dem 4G ändert, regelt der Code zur Laufzeit:

- keine Kamera → kein QR-Scan, Kontakte per npub einfügen
- Mikrofon nur mit Headset → Aufnahmeknopf erscheint nur, wenn eins steckt
- `dict[key]`/`array[i]` gibt es erst ab iOS 6 → `MeshCompat` rüstet die Methoden beim Start nach

Am Gerät prüfen: Installation, Entsperren, Startbildschirm, Chat, Bild empfangen, Sprachnachricht
abspielen, Schlüsselbund (Sicherheitsseite: „Schlüssel an dieses Gerät gebunden“).

## touch 2G (iOS 4.2.1, ARMv6, 128 MB)

Der Code ist vorbereitet (keine iOS-5-APIs ohne Weiche, `arc4random_buf` ersetzt, schwache
Referenzen über `MESH_WEAK`, Delegates werden in `dealloc` gelöst). Es fehlt die Toolchain:

1. **SDK mit ARMv6:** `iPhoneOS5.1.sdk` aus Xcode 4.4.1 (Apple-Entwicklerdownload) nach
   `$THEOS/sdks/`. Neuere SDKs enthalten kein ARMv6 mehr.
2. **libarclite für ARMv6:** aus derselben Xcode-Version
   (`…/usr/lib/arc/libarclite_iphoneos.a`). Unter iOS 4 liefert sie die ARC-Laufzeitfunktionen
   (`objc_retain`, `@autoreleasepool` …), die erst iOS 5 mitbringt — ohne sie startet die App nicht.
3. **Linker mit ARMv6:** ld64 aus Xcode 4.4.1 (läuft nur auf Intel-Macs mit macOS ≤ 10.8)
   oder ein aktueller ld64 aus cctools-port.
4. **Bibliotheken für ARMv6** nach `vendor/*/lib-armv6`:
   - mbedTLS: `tools/build-mbedtls.sh <mbedtls-3.6.7> armv6`
   - secp256k1, qrcodegen, quirc: aus den Quellen mit `-arch armv6 -miphoneos-version-min=4.2`
     und `-D_FORTIFY_SOURCE=0` (die `__*_chk`-Funktionen fehlen auf iOS 4).
5. `make package MESH_DEVICE=2g` — setzt ARMv6, iOS 4.2 und passt `Info.plist` an.

Hardware: keine Kamera, kein eingebautes Mikrofon, 128 MB RAM. Medien werden deshalb nur bei
Bedarf geladen und Bildgrößen begrenzt (siehe ARCHITECTURE.md, Speicher). Sprachaufnahme mit
Headset-Mikrofon hängt davon ab, ob der Software-AAC-Encoder auf ARMv6 verfügbar ist — am Gerät
prüfen; ohne ihn bleibt Abspielen möglich.
