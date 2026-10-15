# Architektur

Mesh ist ein Nostr-Messenger in Objective-C für alte iPods und iPhones (iOS 4.2 bis 6.1).
Der Code ist so geschnitten, dass dieselbe Codebasis auf allen Zielgeräten läuft. Unterschiede
zwischen den iOS-Versionen und der Hardware stecken in genau zwei Modulen (`Compat/MeshCompat`,
`Compat/MeshCaps`).

## Schichten

```
App          AppDelegate, main
UI/*         Lock, Connect, Chats, Chat (+ MeshBubbleCell, MeshNoticeCell, MeshChatInputBar, MeshReplyBar,
             MeshMessageMenu), Contacts, Me (+ Identities), Settings
UI/Common    Bausteine: MeshTopBar, MeshTabBar, MeshPageHeader, MeshMenuRow, MeshControls,
             MeshAvatarView, MeshPopup, MeshBanner, MeshImagePicker, MeshImageViewer, MeshFileViewer,
             MeshClipboard, MeshQR, MeshIdenticon, MeshGlyphs, MeshFormat, MeshTheme
Domain       MeshSession (Fassade für die UI, +Chats), MeshIdentity, MeshMessenger, MeshSignal, MeshPanic,
             MeshInboxWatcher, MeshInboxPolicy, MeshVault, MeshPassphrase, MeshPinGuard, MeshPinStore, MeshKeychain,
             MeshDeviceSecret
Media        MeshVoice, MeshRecorder (Vpio/Pcm, MeshPcmBuffer), MeshVoiceSettings, MeshAudioDSP, MeshAudioCodec, MeshMediaCheck,
             MeshImageCodec, MeshVideoCodec, MeshQRDecoder (quirc)
Transport    MeshRelayPool → MeshRelay → MeshWebSocket → MeshTLS (mbedTLS) [→ MeshTor], MeshCertTime
Storage      MeshStore (sqlite3, Felder verschlüsselt), MeshStore+Migration, MeshStore+Vault,
             MeshStore+Outbox, MeshStore+Chat, MeshStore+Signal, MeshVaultRecord
Protocol     MeshKeys, MeshEvent, MeshEnvelope, MeshNip04, MeshNip44, MeshSignalWire, MeshSignalSession,
             MeshSignalBundle, MeshBech32, MeshContactCode
Model        MeshChat, MeshMessage, MeshPayload, MeshProfile, MeshIdentityInfo
Crypto       MeshCrypto (SHA, HMAC, HKDF, AES-CBC, PBKDF2, Zufall), MeshScrypt, MeshChaCha20, MeshCurve25519,
             MeshSeal, MeshHex
Compat       MeshCompat (iOS-Versionsweichen), MeshCaps (Kamera/Mikrofon), MeshJSON, MeshJSONCodec
Support      MeshBase64, MeshLog, MeshL10n, MeshNotifications, MeshText, MeshMemory
```

Abhängigkeiten zeigen nur nach unten. Im Einzelnen:

| Schicht     | darf benutzen |
|-------------|---------------|
| App         | UI, Domain, Support |
| UI          | Domain, Media, Model, Compat, Support, UI/Common |
| Domain      | Transport, Storage, Protocol, Model, Crypto, Compat, Support |
| Media       | Support, vendor/quirc |
| Transport   | Protocol, Crypto, Compat, Support |
| Storage     | Model, Crypto, Support |
| Protocol    | Crypto, Support |
| Model       | Support |
| Crypto      | Support |
| Compat      | Support |
| Support     | — |

`tests/layers_check.sh` prüft die Tabelle an den `#import`-Zeilen.

Die UI kennt weder Store noch Relays noch Schlüssel. Alles läuft über `MeshSession`.
Neue Funktionen kommen als Methode an die Session, nicht als Import in einen View-Controller.

## Konventionen

- **Namen:** Klassen der Schichten und Bausteine heißen `Mesh…`, View-Controller nicht
  (`ChatViewController`, `CodeViewController`). Kommentare auf Deutsch, Bezeichner auf Englisch.
- **Zustand:** privater Zustand als Ivars im `@implementation`-Block; Properties nur für die
  öffentliche Schnittstelle oder wenn ein Block über eine schwache Referenz zugreift.
- **Layout:** Seitenkopf, Menüzeilen, Felder und Knöpfe kommen aus UI/Common, Maße und Radien aus
  `MeshTheme` — keine kopierten Layout-Blöcke in View-Controllern.
- **Texte:** alles Sichtbare über `L()`/`LF()`; Schlüssel ist der englische Text.

## Threads

- **Main-Thread:** UI, `MeshSession`, `MeshRelayPool`, `MeshStore`, alle Delegate-Callbacks.
- **Je Relay ein Lese-Thread:** blockierendes `readText`, Ergebnisse gehen per `dispatch_async` auf Main.
- **Je Relay eine serielle Schreib-Queue:** Senden und Schließen der TLS-Verbindung.
- **Global Queue:** Aufbereiten und Kodieren von Sprachnachrichten.

`MeshRelay` ändert seinen Zustand (`connected`, Thread) nur auf dem Main-Thread.

## Datenfluss

**Senden:** UI → `MeshSession sendTo:` → `MeshMessenger` → `MeshPayload` (bei Medien) und
`MeshEnvelope` (Nachrichten-ID, Antwort, Timer, eigenes Signal-Bundle) → `MeshSignal` verschlüsseln,
ohne Sitzung `MeshNip44` (über 64 KB `MeshNip04`) → `MeshEvent` signieren → `MeshStore` speichern →
`MeshRelayPool publish:` → alle verbundenen Relays.
Unbestätigte eigene Events liegen versiegelt in `outbox` und gehen bei jeder neuen Verbindung
erneut hinaus; nach sieben Tagen ohne OK zeigt die Blase „nicht zugestellt“.
Ein `OK` setzt den Status auf zugestellt, aber nur von einem Relay, an das das Event auch ging.

**Empfangen:** Relay-Thread → `MeshEvent` parsen und Signatur prüfen → Main → Session wählt die
eigene Identität nach dem p-Tag → `MeshMessenger`: Notlöschungs-Token, Duplikat- und Leerungsprüfung,
entschlüsseln (`sg1:` Signal, sonst NIP-44/NIP-04) → `MeshEnvelope`: Nachricht oder Steueranweisung
(Reaktion, Löschen, Leeren, Timer, Handshake) → Store → `MeshMessagesChangedNotification`.

**Identitäten:** Jede hat eine eigene Datenbank (`MeshIdentity`), alle teilen PIN, Gerätegeheimnis
und den Relay-Pool. Gesperrt im Hintergrund lauscht `MeshInboxWatcher` nur auf DMs an die
öffentlichen Schlüssel (VoIP-Hintergrundmodus) und meldet „Neue Nachricht“ ohne Inhalt.

**Verbindungen:** Die Session sieht nur den Pool (`MeshRelayPoolDelegate`), nie einzelne Relays.
Bei jeder Verbindung fragt der Pool die Abos ab, NIP-42-Anmeldung gibt es einmal je Verbindung.

**Wiederverbinden:** ausschließlich `MeshRelayPool`. Backoff je Relay 5 s, 10 s, … bis 120 s,
ein gemeinsamer 5-s-Takt. Tor meldet Zustandswechsel über `MeshTransportChangedNotification`.

## Speicher

Der iPod touch 2G hat 128 MB RAM. Deshalb:

- Bild-, Sprach- und Dateinachrichten werden in Listen nur mit ihrem Marker geladen (`mesh:img`,
  `mesh:voc:7|`). Die Base64-Daten holt `MeshSession mediaOf:` erst beim Anzeigen oder Abspielen.
- Dekodierte Bilder liegen in `NSCache` mit festen Grenzen. Für Zeilenhöhen werden nur die Bildmaße gemerkt.
- Timer halten ihren Controller fest und werden in `viewWillDisappear` beendet.

## Nachrichtenformat

Format der Android-App (mesh-clean, `MeshNostr.kt`). Der Inhalt einer DM besteht aus Kopfzeilen und
Inhalt bzw. einer Steueranweisung (`Protocol/MeshEnvelope`):

```
\1mesh:x:<cmid>[|r=<cmid>][|t=<s>|tr=<s>]\n     Nachrichten-ID, Antwort auf, Selbstlöschen
\1mesh:mb:<Signal-Bundle>\n                       eigenes Bundle (Wechsel auf Signal)
\1mesh:rx:<ziel>|<emoji>  \1mesh:del:<ziel>  \1mesh:clr:  \1mesh:ttls:<s>|read|sent  mesh:hi:
```

Inhalte (`Model/MeshPayload`): `mesh:img<b64>`, `mesh:voc:<s>|<b64>`, `\1mesh:file:<Name>\1<MIME>\n<b64>`,
`mesh:contact:<Name>\n<Mesh-Code>`; ältere iPod-Formate (`mesh:img:`, `mesh:voice:`) bleiben lesbar.
Verschlüsselt: Signal (`sg1:p:`/`sg1:m:`, libsignal-kompatibel, siehe `tools/dev/interop`), sonst
NIP-44, über 64 KB NIP-04. Notlöschung: leeres Event mit Tag `["mw", p2:<PBKDF2-Token>]`.

## Schlüssel und Entsperr-Code

Der Seckey liegt ausschließlich verschlüsselt im Vault, mit einer von zwei Schutzarten, die man beim
ersten Start wählt (`SetupProtectionViewController`, später unter Sicherheit änderbar):

- **6-stellige PIN:** PBKDF2-HMAC-SHA256, 40 000 Iterationen.
- **5 oder 6 Wörter** (`MeshPassphrase`): von der App mit SecRandom gewürfelt, ≈ 12,9 Bit je Wort,
  Deutsch oder Englisch (Voreinstellung: Sprache der App). Listen mit je 7776 Wörtern:
  de-7776 von dys2p (CC0, `Resources/wordlist-de.txt`) und die EFF Large Wordlist (Electronic
  Frontier Foundation, CC BY 3.0, `Resources/wordlist-en.txt`; geändert: Bindestriche entfernt,
  yo-yo durch yolk ersetzt, weil die Eingabe Satzzeichen ignoriert). Selbst gewählte
  Sätze gibt es nicht. Ableitung mit scrypt (`MeshScrypt`, N = 16384, r = 8, p = 1, 16 MB).
  Verglichen wird normalisiert: klein, nur Buchstaben, ein Leerzeichen zwischen Wörtern.

Salt = 16 Zufallsbytes ‖ Gerätegeheimnis, dann AES-256-CBC. Die Art (`vault.kdf`) liegt lesbar im
Eintrag, damit der Sperrbildschirm Ziffernblock oder Tastatur zeigt. Ein Wechsel der Art entfernt
die Panik-PIN; im Wörter-Modus ist der Panik-Code frei gewählt (ab 4 Buchstaben). Der Pubkey
daneben dient als Prüfwert. `MeshVault` schreibt, liest den Datensatz zurück und vergleicht ihn;
erst danach darf eine ältere Kopie gelöscht werden.

- **Gerätegeheimnis** (`MeshDeviceSecret`): 32 Byte im Schlüsselbund, `ThisDeviceOnly`, nicht in
  Backups. Ohne es ist eine kopierte Datenbank nicht durchprobierbar. Ist der Schlüsselbund nicht
  erreichbar, wird kein Vault geschrieben (PIN festlegen und ändern melden „Schlüsselbund nicht
  erreichbar“); nur Vaults aus der Zeit davor öffnen sich noch ohne und werden dabei gebunden. Ist
  ein Vault gebunden, wird nie ein neues Geheimnis angelegt. Braucht die Entitlements in `ent.plist`.
- **Fehlversuche** (`MeshPinGuard`): vier frei, dann 30 s bis 1 h Sperre. Der Zähler liegt im
  Schlüsselbund (`MeshPinStore`), übersteht also Neustart und Neuinstallation; ist er nicht
  lesbar, bleibt die Eingabe gesperrt. Die Sperre muss auf zwei Uhren ablaufen: Zeit seit
  Gerätestart einschließlich Ruhezustand (Uhrzeit minus `kern.boottime`) und Wanduhr. Uhr
  vorstellen verkürzt nichts; ein Neustart während der Sperre startet sie neu. Am iPod 4G (iOS 6.1.6)
  geprüft: `date -s` um 2 h verschiebt `kern.boottime` um genau 2 h, Ruhezustand verschiebt nichts.
- Der nsec wird nur angezeigt, nie kopiert: Die Zwischenablage kann jede App lesen.
- **Sperren** (Knopf, Home-Taste, Bildschirm aus, jeder Systemdialog: `applicationWillResignActive`,
  weil iOS 4 bis 6 beim Standby-Knopf keinen Hintergrund meldet): vorher geht `MeshWillLockNotification` raus —
  offene Popups schließen ohne Handler, Aufnahmen werden verworfen, Wiedergabe stoppt. Danach
  überschreibt die Session Seckey, Datenschlüssel und Gerätegeheimnis im RAM; ein überschriebener
  `MeshKeys` signiert und leitet nichts mehr ab. Das Gerätegeheimnis wird erst beim Entsperren
  wieder aus dem Schlüsselbund gelesen, die Teilschlüssel von `MeshSeal` nach jedem Aufruf gelöscht.

**Grenze des Modells:** Wer auf einem jailbroken Gerät Root-Zugriff hat, kann Schlüsselbund und
Datenbank zusammen auslesen. Bei der PIN bleiben dann nur 10⁶ Möglichkeiten mal 40 000
PBKDF2-Runden — offline in Sekunden bis Minuten durchprobiert. Sie schützt gegen eine kopierte
Datenbank, ein gestohlenes Backup und Neugierige am entsperrten Gerät, nicht gegen Root. Fünf Wörter
(≈ 65 Bit) mit scrypt halten auch dann: bei grob 7000 Versuchen je Grafikkarte und Sekunde bräuchten
1000 Karten im Mittel etwa 60 000 Jahre, sechs Wörter (≈ 78 Bit) 7776-mal so lange.

## Datenbank

`mesh.sqlite` enthält Nachrichteninhalte, Kontakt- und Profilnamen sowie Bilder nur verschlüsselt
(`MeshSeal`: AES-256-CBC, dann HMAC-SHA256; Format `enc2:` + Base64). Das HMAC deckt neben dem
Chiffrat einen Kontext ab — bei Nachrichten Chat, Art, Zeit, Richtung und Event-ID —, damit sich
versiegelte Felder nicht zwischen Zeilen vertauschen lassen. Der Datenschlüssel ist
HMAC(Seckey, "mesh-db-v1") und existiert nur im entsperrten Zustand; ohne ihn schreibt und liest
der Store diese Felder nicht. Unverschlüsselt bleiben, was Abfragen brauchen: Pubkeys, Zeiten,
Zustellstatus, Art, Länge und Bildmaße von Medien — wer mit wem schreibt, ist also sichtbar, der Inhalt nicht.
`PRAGMA secure_delete` überschreibt Gelöschtes; nach Migrationen läuft `VACUUM`. Die Datei ist mit
`NSFileProtectionComplete` geöffnet (wirkt, wenn ein Gerätecode gesetzt ist).

Sprachnachrichten werden im Speicher aufgenommen (`MeshRecorder`: Voice-Processing-Unit oder
AudioQueue, Puffer vorab in voller Länge und nach dem Kodieren überschrieben), kodiert und
dekodiert (`MeshAudioCodec` über Core-Audio-Callbacks); weder Aufnahmen noch entschlüsselte
Inhalte gehen als Datei nach `tmp/`. Das Diagnose-Log gibt es nur
in Debug-Paketen (`FINALPACKAGE=0`); Release-Builds und „Alles zurücksetzen“ löschen es.

Schema-Version (`PRAGMA user_version`): 3. Ältere Datenbanken werden beim ersten Entsperren
umgeschlüsselt. Dass die Datenbank versiegelt ist, steht zusätzlich im Schlüsselbund — eine
zurückgesetzte `user_version` führt deshalb nicht dazu, dass Klartext wieder angenommen wird.

Inhalte von Bild, Sprache und Datei liegen (gleich versiegelt, gleicher Kontext) in `message_blobs`
(rowid = `messages.rowid`), `messages.content` ist für sie leer: sonst stünden 100–700 KB vor den
kleinen Spalten jeder Zeile, und schon `kind` oder `ts` zu lesen hieße, deren Überlaufseiten
abzulaufen. Ein Trigger löscht den Inhalt mit der Zeile. Ältere Datenbanken zieht
`moveMediaStep` nach dem Entsperren in kleinen Schritten um (je eine Transaktion samt Fortschritt in
`meta`; abgebrochen gilt das Übertragene, der Rest wird weiter aus `messages` gelesen); danach
entstehen die Indizes, die Spalten hinter dem Inhalt lesen.

## Eingaben von außen

Alles vom Relay gilt als feindlich:

- **TLS** prüft Kette (Mozilla-Bundle `Resources/cacert.pem`, `tools/update-cacert.sh`) und
  Hostnamen. Gültigkeitszeitraum prüft `MeshCertTime` nur bei plausibler Uhr (alte iPods fallen
  bei leerem Akku auf 1970).
- **WebSocket**: Nachrichten ≤ 4 MB, strenge Frame-Regeln, Handshake mit Accept-Prüfung.
- **JSON/Events**: Typprüfung nach NIP-01, Profile nur von bekannten Kontakten.
- **Medien**: Bilder nur JPEG/PNG bis 2048 px und 3,1 MP, Audio nur M4A/ADTS — geprüft im
  eigenen Code, bevor ein System-Decoder die Daten sieht. Bilder und Profilbilder von nicht
  angenommenen Kontakten erst nach Bestätigung.
- **Flut** (`MeshInboxPolicy`): höchstens 50 unbestätigte Kontakte, von Fremden zusammen höchstens
  20 MB und je Kontakt 100 Nachrichten bzw. 5 MB; für einen neuen Fremden wird der älteste
  verdrängt. Text ≤ 64 KB, Bild ≤ 1 MB, Sprache ≤ 2 MB. Gelöschte Chats bleiben gelöscht (auch
  wenn ein Relay die alten Events erneut schickt), Absender lassen sich blockieren. DMs werden
  nur ab drei Tagen vor der neuesten empfangenen Nachricht abgeholt.
- **JSON**: rohe Nullbytes werden abgelehnt, bevor der System-Parser sie als UTF-16 lesen kann.
- **Tor**: ist es aktiv, wird nie direkt verbunden. Stand: vorbereitet, aber ohne libtor gebaut
  (`MESH_USE_TOR=0`); der SOCKS5-Weg in `MeshTLS` ist deshalb noch nicht am Gerät erprobt. Mit
  libtor statt des festen Ports 9050 einen zufälligen Port mit SOCKS-Anmeldung verwenden.

## iOS-Versionen und Geräte

| Gerät            | iOS   | CPU    | RAM    | Kamera | Mikrofon |
|------------------|-------|--------|--------|--------|----------|
| iPod touch 2G    | 4.2.1 | ARMv6  | 128 MB | nein   | nur Headset |
| iPod touch 3G    | 5.1.1 | ARMv7  | 256 MB | nein   | nur Headset |
| iPod touch 4G    | 6.1.6 | ARMv7  | 256 MB | ja     | ja |

- `MeshCompat` kapselt alles, was es erst ab iOS 5/6 gibt: Subscripting (`dict[key]`, wird beim
  Start nachgerüstet), `presentViewController`,
  `wantsFullScreenLayout`, `NSJSONSerialization` (sonst eigener Parser `MeshJSONCodec`),
  `__weak` (unter iOS 4 nur `unsafe_unretained`), PBKDF2 aus CommonCrypto (sonst eigene Umsetzung).
- `MeshCaps` fragt Kamera und Mikrofon zur Laufzeit ab. Ohne Kamera gibt es keinen QR-Scan,
  ohne Mikrofon keine Sprachaufnahme. Abspielen geht immer.
- Unter iOS 4 sind schwache Referenzen nicht nil-sicher: Jedes Objekt, das sich als Delegate
  einträgt, trägt sich in `dealloc` wieder aus.

Übriger Code fragt weder die iOS-Version noch die Verfügbarkeit von APIs ab;
`respondsToSelector:` kommt nur für optionale Delegate-Methoden vor.

## Tests

`tests/run.sh` läuft auf dem Mac ohne Gerät und endet mit einer Übersicht (Exit-Code ≠ 0 bei Fehlern):

- Krypto und Protokoll gegen offizielle Testvektoren (`tools/selftest.sh`)
- JSON-Parser gegen `NSJSONSerialization` (inkl. Fuzzing)
- PBKDF2 gegen CommonCrypto und RFC 7914
- Base64 gegen RFC 4648
- Nachrichtenformat inkl. kaputter Eingaben
- Relay-Pool mit Schein-Relays (`tests/fakes`)
- Store auf einer temporären Datenbank
- Audio-Codec und Signalverarbeitung
- Vault mit einem Speicher im RAM, inklusive Gerätegeheimnis und Migration
- Datenbank-Verschlüsselung (kein Klartext in der Datei, Migration alter Daten)
- NIP-44 (offizielle Vektoren, ChaCha20 RFC 8439, HKDF RFC 5869), Curve25519 (RFC 7748/8032)
- Signal zwischen zwei Instanzen; gegen libsignal-protocol-java 2.8.1 (Android) prüft
  `tools/dev/interop/run.sh` beide Richtungen, Reihenfolge, große Nachrichten, Sicherheitsnummer
- Messenger: zwei Geräte im RAM (Antworten, Reaktionen, Löschen, Leeren, Selbstlöschen,
  Notlöschung, Signal-Handshake), Umschlag und Kontakt-Codes im Android-Format
- Texte (jeder Schlüssel in en und de) und Schichtgrenzen (`#import` gegen die Tabelle oben)
- Angriffstests: WebSocket-Frames, Bech32, Relay-Nachrichten und Events, Bildköpfe (Fuzzing),
  Manipulation versiegelter Felder, PIN-Sperre, Zertifikatszeit

Was nur am Gerät geht: TLS gegen echte Relays (`tools/dev/build-tlsprobe.sh`), Schlüsselbund,
Tor, Kamera, Mikrofon, RAM-Verhalten, VoIP-Hintergrund. Ob die App selbst baut, zeigt nur der
Exit-Code von `make package` (Fehler in Theos-Headern stehen nicht unter `mesh/`).
