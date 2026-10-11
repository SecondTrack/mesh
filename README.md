# Mesh

**Verschlüsselter Messenger ohne Telefonnummer – über das Tor-Netzwerk**

Dezentraler, verschlüsselter Messenger über Nostr und Tor. Anonym, ohne Telefonnummer, ohne zentralen Server – Chats, Sprachnachrichten und Bilder.

## Das kann die App

- Chats ohne Telefonnummer – nur ein Schlüssel
- Ende-zu-Ende-verschlüsselt, Datenbank auf dem Gerät verschlüsselt
- Sprachnachrichten und Bilder
- Läuft über Tor – kein zentraler Server
- Sperre mit PIN

## Läuft auf

iOS 5.1.1, iOS 6.1.6 · gejailbreakter iPod touch

## Installieren

Am einfachsten über den **[Reboot Appstore](https://github.com/SecondTrack/reboot)** direkt auf dem iPod.
Von Hand: das `.deb` aus dem [neuesten Release](https://github.com/SecondTrack/mesh/releases/latest) laden und mit `dpkg -i` installieren, danach `uicache`.

## Selbst bauen

Mit [Theos](https://theos.dev) (iOS-SDK mit armv7):

```sh
make package
```

## Teil von Reboot

Diese App gehört zu **Reboot** von [Second Track](https://secondtrack.de) – neue Apps für alte iPods.
Alle Apps: [SecondTrack](https://github.com/SecondTrack).

## Lizenz

GPL-3.0 – siehe [LICENSE](LICENSE). Mitgelieferte Bibliotheken unter `vendor/` behalten ihre eigenen Lizenzen.
Nicht mit Apple verbunden. iPod ist eine Marke von Apple Inc.

---

# Mesh für alte iPods

Verschlüsselter Nostr-Messenger für jailbroken iPod touch und iPhone mit iOS 4.2 bis 6.1.
Gegenstück zur Android-App Mesh: gleiches Design, gleiches Nachrichtenformat, untereinander kompatibel.

WhatsApp, Signal und Telegram sperren alte Clients serverseitig aus. Nostr-Relays tun das nicht:
Ein eigener Client funktioniert, solange er das Protokoll spricht.

## Stand

| Gerät         | iOS   | Status |
|---------------|-------|--------|
| iPod touch 4G | 6.1.6 | läuft  |
| iPod touch 3G | 5.1.1 | dasselbe Paket, Gerätetest offen |
| iPod touch 2G | 4.2.1 | Code bereit, braucht ARMv6-Toolchain (docs/PORTING.md) |

Funktionen: eigene secp256k1-Identität ohne Account, NIP-04-verschlüsselte Direktnachrichten,
Bilder und Sprachnachrichten (mit Stimmeffekten), QR-Code zum Teilen und Scannen, Safety-Number
zum Verifizieren von Kontakten, Entsperr-Code mit Sperrzeit und Gerätebindung, verschlüsselte
Datenbank, TLS mit Zertifikatsprüfung. Sicherheitsmodell: docs/ARCHITECTURE.md.

Nicht enthalten: eigener Hidden-Service wie bei Android. Ein optionaler Tor-Transport ist vorbereitet
(`MESH_USE_TOR`), aber noch nicht am Gerät erprobt.

## Bauen

Voraussetzungen: [Theos](https://theos.dev), iOS-7.1-SDK unter `$THEOS/sdks/`, die gevendorten
Bibliotheken unter `vendor/` (Anleitung in `vendor/README.md`).

```sh
export THEOS=~/theos
make package                    # Release-Build, ohne Log
make package FINALPACKAGE=0     # Debug-Build, schreibt Documents/mesh.log (nur Testgeräte)
```

Wenn `xcrun` mit einer arm64e-Meldung abbricht, ist ein altes Xcode ausgewählt:
`export DEVELOPER_DIR=/Library/Developer/CommandLineTools`.

Installieren: `.deb` aus `packages/` per SSH auf das Gerät kopieren, `dpkg -i`, dann `uicache`.

## Testen

```sh
tests/run.sh                    # alle Mac-Tests, ca. 30 s
tools/dev/build.sh              # Gegenstelle (nostrbot), Einzelversand, Relay-Abfrage
```

Für die Krypto- und Vault-Tests: `brew install secp256k1`.

## Aufbau

Schichten, Threads, Datenfluss und die Regeln für die verschiedenen iOS-Versionen:
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

```
mesh/        App-Code, eine Schicht je Ordner
tests/       Mac-Tests (tests/run.sh)
tools/       selftest, Entwicklerwerkzeuge (dev/), Icon-Erzeugung (assets/)
vendor/      secp256k1, mbedTLS, qrcodegen, quirc
docs/        Architektur und Sicherheitsmodell, Portierung, Design-Vorschau
```

## Offene Punkte

- Gerätetests auf touch 3G und 4G (Liste in docs/PORTING.md), TLS-Probe mit mbedTLS 3.6.7 am Gerät.
- touch 2G: ARMv6-Toolchain und Bibliotheken (docs/PORTING.md).
- Tor-Transport: libtor für ARMv7 bauen und am Gerät erproben (`MESH_USE_TOR`).
- NIP-44 statt NIP-04 — erst zusammen mit der Android-App, sonst können beide nicht mehr reden.
- Metadaten: Pubkeys und Zeitstempel liegen unverschlüsselt in der Datenbank.
