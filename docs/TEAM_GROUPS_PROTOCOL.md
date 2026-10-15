# Mesh: Team-Chat und Gruppen – gemeinsames Protokoll v1 (iPod + Android)

Beide Apps implementieren GENAU dieses Format. Alles hier ist verbindlich; Abweichungen = inkompatibel.
Bestehende Formate (MeshEnvelope.h auf dem iPod, MeshState.kt/MeshNostr.kt auf Android) gelten weiter.
`\1` = U+0001. Base64 = Standard-Alphabet mit Padding, ohne Zeilenumbrüche. JSON = UTF-8, kompakt
erzeugen, tolerant lesen (unbekannte Felder ignorieren). pk = 64 Hex-Zeichen klein (x-only secp256k1).
gid = 16 Hex-Zeichen klein (8 Zufallsbytes). Alle Hex-Werte beim Lesen prüfen und klein machen.

---------------------------------------------------------------------------------------------------
## Teil A: Team-Chat "Mesh Team"

### A1. Konstanten (je App genau EINE Stelle im Code)
- `TEAM_PK`  – pk der Support-Identität des Entwicklers. Bis zur echten Identität ein Platzhalter
  `0000…0000` (64 Nullen): dann ist der Team-Chat komplett aus (kein Eintrag, kein Netzverkehr).
- `TEAM_CARD` – Mesh-Code derselben Identität im Kontaktkarten-Format (`mesh:<npub>[?sig=<bundle>]`),
  Name auf der Karte: "Mesh Team". Platzhalter leer = keine Karte in der Begrüßung.
- Ist die eigene aktive Identität == TEAM_PK: kein Team-Chat, dafür die Entwickler-Funktionen (A6).

### A2. Rundbriefe "an alle" (Entwickler -> alle, öffentlich, nur Lesen)
- Nostr-Event kind 1, pubkey == TEAM_PK, Tag `["t","mesh-team"]` Pflicht, gültige Signatur Pflicht.
- content = JSON `{"v":1,"de":"<Text>","en":"<Text>"}`; mindestens eins von de/en nicht leer.
  Anzeige in Gerätesprache, sonst die andere. Jeder Text höchstens 4000 Zeichen (länger = verwerfen).
  Unsichtbare/Steuerzeichen außer \n entfernen. NUR Text: keine Links anklickbar, keine Marker
  auswerten (enthält der Text `\1mesh:` -> verwerfen).
- created_at > jetzt + 15 min -> verwerfen. Älter als 90 Tage beim ersten Abruf -> nicht holen.
- Löschen: kind 5 von TEAM_PK mit `["e","<event-id>"]` -> diesen Rundbrief entfernen.
- Abo: `{"kinds":[1,5],"authors":[TEAM_PK],"since":<jetzt-90d beim 1. Mal, danach letzter+1>}` auf den
  normalen Relays. Gespeichert verschlüsselt wie Nachrichten, Event-ID gegen Doppelte.
- Veröffentlichen (Entwickler): an die Relays BEIDER Apps (Android RelayRouting.RELAYS und die
  iPod-Liste in MeshSession), damit jeder sie findet.

### A3. Anonyme Antworten (Nutzer <-> Entwickler)
- Pro Gerät/Identität ein Einweg-Schlüssel E (secp256k1, zufällig, NIE aus der echten Identität
  abgeleitet), verschlüsselt gespeichert wie die anderen Schlüssel, beim Sperren aus dem RAM.
  "Neu anfangen" = Team-Chat-Verlauf (nur persönliche Nachrichten) löschen + neuer E.
- Nutzer schreibt: kind-4-DM von E an TEAM_PK, Tag `["p",TEAM_PK]`, verschlüsselt NUR mit NIP-44
  (kein Signal, kein Bundle, kein Profilbild, kein mesh:on, keine Panik-Felder). Klartext:
  `\1mesh:anon:1\n` + `\1mesh:x:<cmid>\n` + `<Text>`. Nur Text, höchstens 4000 Zeichen.
- Entwickler antwortet ganz normal per kind-4-DM an E (NIP-44, ohne Bundle, weil E keins hat).
  Der Nutzer akzeptiert in diesem Kanal NUR Events von TEAM_PK an E.
- Netz-Trennung (wichtig für die Anonymität): Abo und Senden für E laufen über eine EIGENE
  Relay-Verbindung mit eigenem Tor-Kreis (eigene SOCKS-Zugangsdaten -> IsolateSOCKSAuth), nie über
  die Verbindung der echten Identität. Abo: `{"kinds":[4],"#p":[E],"authors":[TEAM_PK]}`.
  Geht keine getrennte Verbindung, wird für E nichts gesendet/abonniert (fail-closed).

### A4. Darstellung beim Nutzer (sieht aus wie ein normaler Chat)
- Eintrag "Mesh Team" in der Chatliste, oben angeheftet, eigenes Bild (App-Icon/Mesh-Glyph).
- Chat sieht aus wie jeder andere: Blasen, Uhrzeit, Eingabefeld. Rundbriefe als eingehende Blasen
  mit kleiner Zeile "an alle" / "to everyone" darüber; persönliche Antworten ohne diese Zeile.
- Anhang-, Sprach-, Kamera-Knöpfe ausgeblendet (nur Text). Kein Teilen/Verifizieren/Weiterleiten.
- Ganz oben fester Hinweis: DE "Anonym: Das Team sieht nicht, wer du bist – nur was du hier
  schreibst." EN "Anonymous: the team can't see who you are – only what you write here."
- Erste Blase: Begrüßung, lokal in der App (nie übers Netz), Zeit = erster Start. Danach eine ganz
  normale Kontaktkarte "Mesh Team" (TEAM_CARD), genau so gerendert und antippbar wie jede empfangene
  Kontaktkarte. Darunter in der Begrüßung der Satz: "Fügst du ihn als Kontakt hinzu, sieht das Team
  deine Mesh-ID." Begrüßungstexte: siehe A7.
- Chat-Menü: "Stumm", "Neu anfangen" (mit Bestätigung), "Ausblenden" (in Einstellungen wieder an).
- Ungelesen-Zähler und Benachrichtigung wie bei normalen Chats.

### A5. Kontaktkarte "Mesh Team"
Fügt der Nutzer die Karte hinzu, ist TEAM_PK ein normaler Kontakt mit normalem Chat (nicht anonym).
Der Team-Chat bleibt daneben bestehen (anderer Eintrag).

### A6. Entwickler-Seite (nur Android, nur wenn aktive Identität == TEAM_PK)
- Chats von Absendern, deren erste Nachricht `\1mesh:anon:1` trägt, heißen "Anonym · <erste 4 Hex
  des Absenders>" und landen direkt im Chat (nicht als Anfrage, aber ohne Profil/Kontaktaustausch).
  Antworten gehen über Relays an E. Kein Bundle, kein Profilbild, kein mesh:on an solche Absender.
- "An alle senden": Seite mit Feldern DE und EN, Bestätigungsdialog, signiert kind 1 wie A2.
  Liste der gesendeten Rundbriefe mit "Löschen" (kind 5).

### A7. Begrüßung (lokal)
DE: "Hallo und willkommen bei Mesh! 👋\nHier bekommst du Neuigkeiten und Updates. Wenn etwas nicht
klappt oder du eine Idee hast, schreib einfach hier – anonym.\nDirekt mit dem Entwickler schreiben
(auch mit Bildern): Kontakt unten hinzufügen. Dann sieht das Team deine Mesh-ID."
EN: "Hi and welcome to Mesh! 👋\nThis is where you get news and updates. If something doesn't work
or you have an idea, just write here – anonymously.\nTo chat with the developer directly (with
pictures too): add the contact below. The team will then see your Mesh ID."

---------------------------------------------------------------------------------------------------
## Teil B: Gruppen

Prinzip: Fan-out. Jede Gruppennachricht geht einzeln über den bestehenden 1:1-Weg (Signal, sonst
NIP-44/NIP-04, Transport wie beim jeweiligen Kontakt; Nicht-Kontakte über Relays) an jedes Mitglied.
Kein gemeinsamer Gruppenschlüssel. Höchstens 20 Mitglieder inkl. Admin. Ein Admin (Ersteller).

### B1. Gruppenzustand
JSON:
`{"v":1,"g":"<gid>","n":"<Name>","a":"<admin pk>","r":<Revision int>,"m":["<pk>",…],
  "nm":{"<pk>":"<Anzeigename>",…},"t":<Timer s, 0=aus>,"tm":"read"|"sent"}`
- n: 1–50 Zeichen nach Entfernen unsichtbarer/Steuerzeichen. m enthält den Admin, keine Doppelten,
  1–20 Einträge. nm: Name je Mitglied (je ≤ 40 Zeichen, gleiche Säuberung), fehlende = leer.
- Gültig nur, wenn das tragende Event von `a` signiert ist. Bekannte Gruppe: a muss gleich bleiben
  und r größer als gespeichert sein, sonst verwerfen.

### B2. Steueranweisungen (Klartext im 1:1-DM, nie mit Bundle-Zeile)
- Einladung (Admin -> Eingeladenen): `\1mesh:gi:` + Base64(Zustand-JSON)
  Nur annehmen, wenn Absender == a UND Absender ein angenommener Kontakt ist; sonst verwerfen.
  Erscheint als Gruppeneintrag mit Einladung (Annehmen / Ablehnen), siehe B5.
- Beitreten (Eingeladener -> Admin): `\1mesh:gj:<gid>|<Base64(eigener Anzeigename)>`
  Admin nimmt nur an, wenn er diesen pk eingeladen hat und die Gruppe < 20 hat; dann r+1,
  Mitglied in m/nm, Zustand an ALLE Mitglieder (inkl. neuem).
- Ablehnen: nichts senden (unsichtbar). Admin vergisst offene Einladungen nach 30 Tagen.
- Zustand (Admin -> alle Mitglieder): `\1mesh:gs:` + Base64(Zustand-JSON). Gilt bei Umbenennen,
  Entfernen, Beitritt, Timer. Entfernte bekommen den neuen Zustand ebenfalls (ohne sich darin) ->
  Gruppe bei ihnen "Du bist nicht mehr in der Gruppe", nur noch lesbar.
- Verlassen (Mitglied -> Admin und alle): `\1mesh:gl:<gid>` -> Empfänger senden diesem pk sofort
  nichts mehr; Admin entfernt ihn (r+1, Zustand an alle). Verlässt der Admin, ist die Gruppe
  aufgelöst: er sendet vorher Zustand mit m=[] (r+1) an alle -> bei allen "Gruppe aufgelöst".
- Größe: Base64 einer Steueranweisung ≤ 16 KB, sonst verwerfen.

### B3. Gruppennachrichten
Klartext = zusätzliche Kopfzeile `\1mesh:g:<gid>\n` VOR den bestehenden Kopfzeilen:
`\1mesh:g:<gid>\n\1mesh:x:<cmid>[|r=<cmid>][|t=..|tr=..]\n[\1mesh:mb:<bundle>\n]<Inhalt>`
- Inhalt wie bei 1:1 (Text, Bild, Sprache, Kontaktkarte). Große Dateien (mesh:fc) in Gruppen nicht.
- Dieselbe cmid an alle Mitglieder. Doppelte (gleicher Absender + cmid) verwerfen.
- Auch Reaktion und Löschen-für-alle in Gruppen: `\1mesh:g:<gid>\n\1mesh:rx:<cmid>|<emoji>` bzw.
  `\1mesh:g:<gid>\n\1mesh:del:<cmid>`. Chat leeren ist in Gruppen nur lokal.
- Annehmen nur, wenn ich der Gruppe beigetreten bin und der Absender in meinem m steht. Dann gilt
  NICHT die Fremden-Regel (Nachrichtenanfrage), aber die normalen Größengrenzen.
- Panik-Codewort im Gruppentext löst NICHT aus (nur 1:1 wie bisher).
- Selbstlöschen: t/tm aus dem Zustand; Nachrichten tragen t/tr wie bei 1:1.
- Mitglieder, die keine Kontakte sind: nicht in der Kontaktliste, keine Nachrichtenanfrage, kein
  Profilbild-Austausch; angezeigt mit nm-Name + Identicon. Man kann sie aus der Gruppe heraus als
  Kontakt hinzufügen (normaler Weg).

### B4. Alte Versionen
iPod ignoriert Unbekanntes mit `\1mesh:` schon. Android bekommt zusätzlich: jeder Text, der mit
`\1mesh:` beginnt und keinen bekannten Marker hat, wird verworfen (nicht als Text gezeigt).

### B5. Darstellung
- Chatliste: Gruppe mit rundem Gruppenbild (Identicon aus gid + Gruppen-Glyph), Name, letzte
  Nachricht "Anna: Text". Einladung: Eintrag "Einladung: <Gruppe>" von <Admin-Name>.
- Gruppenchat: wie 1:1, eingehende Blasen mit farbigem Absendernamen darüber (Farbe aus pk),
  Systemzeilen "Anna ist beigetreten", "Ben hat die Gruppe verlassen", "Gruppe umbenannt in …".
- Einladung öffnen: Gruppenname, Admin, Mitgliederliste und Hinweis "Wenn du beitrittst, sehen alle
  Mitglieder deine Mesh-ID, und du ihre." + Annehmen / Ablehnen.
- Kopfzeile antippen -> Gruppenprofil: Name, Mitglieder (Admin markiert), Medien,
  Admin: Mitglied hinzufügen (aus Kontakten), Mitglied entfernen, Umbenennen, Selbstlöschen;
  alle: Gruppe verlassen (Admin: "Gruppe auflösen").
- Neue Gruppe: in der Chatliste "+" / Menü -> "Neue Gruppe" -> Kontakte wählen (max. 19) ->
  Name -> fertig. Einladungen gehen sofort raus; Eingeladene erscheinen bis zum Beitritt als
  "eingeladen" (nur beim Admin).

### B6. Prüfvektoren (beide Apps als Unit-Test)
gid `0123456789abcdef`, Admin `aa…aa` (64×a), Mitglied `bb…bb` (64×b).
Zustand-JSON (exakt so erzeugt): `{"v":1,"g":"0123456789abcdef","n":"Test","a":"<64×a>","r":2,"m":["<64×a>","<64×b>"],"nm":{"<64×a>":"Anna","<64×b>":"Ben"},"t":0,"tm":"read"}`
Gruppentext: `\1mesh:g:0123456789abcdef\n\1mesh:x:00112233aabbccdd\nHallo` -> gid, cmid
`00112233aabbccdd`, Text "Hallo". Beitreten: `\1mesh:gj:0123456789abcdef|QmVu` -> Name "Ben".
Rundbrief-content `{"v":1,"de":"Hallo","en":"Hi"}` -> DE "Hallo", EN "Hi".
Anon-Klartext `\1mesh:anon:1\n\1mesh:x:00112233aabbccdd\nBug` -> anon, cmid, Text "Bug".
Ungültig (muss verworfen werden): gid mit 15 Zeichen, Zustand mit 21 Mitgliedern, Zustand von
Nicht-Admin, r nicht größer, Name leer, Rundbrief ohne t-Tag, Rundbrief mit `\1mesh:` im Text.

### B7. Gruppenbild (Nachtrag v1, gleiche Regeln auf beiden Apps)
- Zustand-JSON bekommt das optionale Feld `"p":"<16 Hex>"` = die ersten 16 Hex-Zeichen von
  SHA-256 über die rohen Bildbytes. Fehlt `p` oder ist es leer: kein Bild (Identicon). Beim Erzeugen
  wird `p` nur geschrieben, wenn ein Bild gesetzt ist (der B6-Prüfvektor ohne Bild bleibt byte-gleich).
  Einordnung beim Erzeugen: `p` direkt nach `"tm"` als letztes Feld.
- Nur der Admin ändert das Bild: neues Bild = r+1, Zustand mit neuem `p` an alle (`gs`), und an jedes
  Mitglied zusätzlich `\1mesh:gp:<gid>|<Base64(Bildbytes)>`. Bild entfernen = Zustand ohne `p` (r+1),
  kein gp.
- Bild: JPEG oder PNG (Magic Bytes prüfen), höchstens 64 KB roh, beim Erzeugen 256×256 px, Qualität
  wie beim Profilbild. Anzeige erst nach Prüfung über den eigenen sicheren Decoder (iPod MeshImageCodec).
- Annehmen von gp: Absender == Admin der Gruppe, ich bin beigetreten, und SHA-256-Präfix der Bytes ==
  `p` des aktuell gespeicherten Zustands. Kommt gp vor dem passenden Zustand an: höchstens EIN
  wartendes Bild je Gruppe merken (nur RAM) und anwenden, sobald ein Zustand mit passendem `p` kommt.
  Alles andere verwerfen.
- Neue Mitglieder: Admin schickt nach dem Beitritt Zustand (mit p) und gp an das neue Mitglied.
- Gilt auch für die Einladung: Einladungsseite zeigt das Bild noch nicht (erst nach Beitritt).
- Prüfvektor: Bildbytes = ASCII "abc" -> p = "ba7816bf8f01cfea". gp-Text
  `\1mesh:gp:0123456789abcdef|YWJj` -> gid 0123456789abcdef, Bytes "abc" (als Bild dann wegen fehlender
  Magic Bytes verworfen, Parser muss es aber zerlegen können).

### B8. Klarstellungen nach der Fehleranalyse (verbindlich, beide Apps)
1. Einladen erhöht immer die Revision: Admin erzeugt bei JEDER Einladung (auch Wiedereinladung) einen
   Zustand mit r+1 (Mitglieder unverändert), speichert ihn, verteilt ihn an die aktuellen Mitglieder und
   schickt ihn in `gi`. So nehmen auch früher Entfernte/Ausgetretene die Einladung an.
2. Keine Dateien/Videos in Gruppen (inline `mesh:file` und `mesh:fc`): Senden in Gruppen sperren
   (Knopf ausblenden), Empfang verwerfen. Erlaubt: Text, Bild, Sprache, Kontaktkarte.
3. Medien-Grenzen in Gruppen (Inhaltslänge Base64): Bild ≤ 256 KB, Sprache ≤ 512 KB; größer = nicht
   senden (Hinweis "zu groß für Gruppen") bzw. beim Empfang verwerfen. Fan-out schrittweise senden.
4. Gruppennachricht/Reaktion/Löschen, die vor dem passenden Zustand ankommt (ich noch nicht Mitglied
   oder Absender noch nicht in m): NICHT endgültig als erledigt merken. Höchstens 50 Events je Gruppe
   bis 15 min im RAM puffern und nach jedem angewandten Zustand erneut prüfen; danach verwerfen,
   aber ohne dauerhaften "erledigt"-Vermerk (Relays dürfen es später erneut liefern).
   Endgültig verwerfen nur: unbekannte gid, Status verlassen/entfernt/aufgelöst, ungültiges Format.
5. Einladung von einem Absender, der (noch) kein angenommener Kontakt ist: nicht anzeigen, aber auch
   nicht endgültig als erledigt merken; bis 30 Tage (höchstens 20) gespeichert zurückhalten und
   anzeigen, sobald der Kontakt angenommen wird (Admin-Bedingungen gelten weiter). Admin-UI bietet
   "Erneut einladen" für eingeladene, noch nicht beigetretene Personen (neue Einladung, r+1).
6. Namenssäuberung identisch (Gruppenname n, Mitgliedsnamen nm, Beitrittsname): entfernen aller
   Zeichen der Unicode-Kategorie Cc und Cf (u. a. \t \n \r, U+00AD, U+061C, U+180E, U+200B–U+200F,
   U+202A–U+202E, U+2060–U+2064, U+2066–U+2069, U+FEFF) AUSSER U+200D (ZWJ, für Emoji-Folgen),
   dann führende/abschließende Leerzeichen entfernen; Leerzeichenfolgen bleiben wie sie sind.
   Danach Länge prüfen (Gruppenname 1–50, Namen ≤ 40, länger = kürzen bei Beitrittsname, sonst verwerfen).
   Längen in UTF-16-Einheiten zählen; nicht mitten in einem Surrogatpaar kürzen.
7. `gl` vom Admin bedeutet Auflösung (wie gs mit m=[]). Admin sendet beim Auflösen gs(m=[]) UND gl.
8. Admin "Chat löschen" bei aktiver Gruppe: eigener Dialog "Die Gruppe wird für alle aufgelöst".

### B9. Admin übergeben und Mitglieder schlagen vor (Nachtrag, beide Apps)
**Admin übergeben**
- Nur der aktuelle Admin kann übergeben, an ein Mitglied aus m. Er sendet einen Zustand mit r+1 und
  neuem `a` (das neue Admin-pk, muss in m stehen) an alle Mitglieder und offenen Einladungen.
- Annahme: Zustand kommt vom GESPEICHERTEN Admin (Event von ihm signiert), r größer, neues `a` ∈ m.
  Danach gilt nur noch das neue `a` als Admin. (Ersetzt für diesen Fall die B1-Regel "a bleibt gleich".)
  Gleiches `a` wie gespeichert: normale B1-Regeln.
- Offene Einladungen des alten Admins verfallen: Wer noch eingeladen (nicht beigetreten) ist und einen
  Zustand mit anderem `a` bekommt, verwirft die Einladung (Hinweis "Einladung abgelaufen"). Der alte
  Admin vergisst seine offenen Einladungen. Der neue Admin kann neu einladen.
- Systemzeile bei allen: "<Name> ist jetzt Admin".
- Admin tritt aus: Gibt es weitere Mitglieder, fragt die App "Admin übergeben an … und austreten" oder
  "Gruppe für alle auflösen". Beim Übergeben-und-Austreten: erst Übergabe-Zustand (r+1), dann `gl` an
  alle; der neue Admin entfernt ihn dann wie bei jedem Austritt (r+1).
- Ältere App-Versionen ohne B9 lehnen den Wechsel ab (dort "a bleibt gleich"); das ist bekannt.

**Vorschlagen (Mitglied -> Admin)**
- Mitglied M schlägt einen eigenen angenommenen Kontakt C vor:
  an Admin: `\1mesh:gpr:<gid>|<C-pk>|<Base64(Anzeigename von C, ≤ 40 nach B8.6)>`
  an C:     `\1mesh:gvo:<gid>|<Admin-pk>|<Base64(Gruppenname ≤ 50 nach B8.6)>`   ("Bürgschaft")
- Admin nimmt gpr nur von beigetretenen Mitgliedern an (Absender ∈ m), C nicht schon Mitglied/eingeladen,
  höchstens 20 offene Vorschläge je Gruppe, 5 je Vorschlagendem, verfallen nach 30 Tagen (verschlüsselt
  gespeichert). Im Gruppenprofil des Admins: Abschnitt "Vorschläge": "<M> schlägt <C> vor" mit
  Einladen / Ablehnen. Einladen = normale Einladung (B8.1). Ablehnen = still verwerfen.
- C nimmt gvo nur von einem angenommenen Kontakt an (höchstens 20, 30 Tage, verschlüsselt gespeichert).
  Eine Bürgschaft erlaubt, dass eine Einladung (gi) für genau diese gid von genau diesem Admin-pk
  angezeigt wird, obwohl der Admin kein angenommener Kontakt ist (Ausnahme von B2/B8.5). Die
  Einladungsseite zeigt dann zusätzlich: "<M> hat dich vorgeschlagen. Den Admin <Name ~abcd> kennst du
  noch nicht." Ohne passende Bürgschaft gilt B8.5 unverändert. gvo selbst erzeugt keine sichtbare
  Nachricht.
- Prüfvektoren: `\1mesh:gpr:0123456789abcdef|<64×c>|Q2Fyb2w=` -> gid, pk c…c, Name "Carol".
  `\1mesh:gvo:0123456789abcdef|<64×a>|VGVzdA==` -> gid, Admin a…a, Gruppenname "Test".

### B10. Offene Gruppen mit Beitritts-Link (Nachtrag, beide Apps)
- Admin schaltet im Gruppenprofil "Offen – jeder mit Link kann beitreten" ein. Dabei erzeugt er ein
  Geheimnis `k` (16 Zufallsbytes, 32 Hex), gespeichert verschlüsselt NUR beim Admin. Zustand bekommt
  das optionale Feld `"o":1` (nur geschrieben wenn offen; Position: nach "tm", vor "p"); r+1 an alle.
- Link (Text, auch als QR): `meshg:1:<gid>:<admin-pk>:<k>` – alles klein-hex. Teilen wie eine
  Kontaktkarte (eigener Kartentyp im Chat: Marker `\1mesh:glink:` + Gruppenname-Base64 + "\n" + Link;
  Antippen = Beitritts-Seite) oder per QR/Kopieren.
- Beitreten per Link: Die App zeigt Gruppe (Name aus der Karte, sonst "Gruppe"), Admin "Name ~abcd" und
  den Hinweis "Alle Mitglieder sehen deine Mesh-ID, und du ihre. Jeder mit diesem Link kann beitreten."
  Bestätigen -> lokaler Eintrag (Status "tritt bei") mit gid + Admin-pk aus dem Link, dann an den
  Admin: `\1mesh:gj:<gid>|<Base64(Name)>|<k>`.
- Admin nimmt gj mit k an, wenn: Gruppe offen, k stimmt (konstante Zeit vergleichen), Gruppe < 20,
  Absender nicht gesperrt (blocked) und nicht in den letzten 24 h vom Admin entfernt. Dann wie Beitritt
  (r+1, gs an alle inkl. neuem). Höchstens 10 Link-Beitritte pro Stunde je Gruppe, Rest verwerfen.
- Der Beitretende nimmt den ersten Zustand an, wenn er vom Admin-pk aus dem Link kommt, gid passt und
  er in m steht (Ausnahme von "Einladung nur von angenommenen Kontakten" – er hat selbst bestätigt).
  Kommt nach 7 Tagen nichts: Eintrag "Beitritt fehlgeschlagen", entfernbar.
- Admin schaltet "Offen" aus oder "Link zurücksetzen": neues k (bzw. keins), r+1 mit/ohne "o";
  alte Links gehen nicht mehr. Bei Admin-Übergabe (B9) wird die Gruppe geschlossen (kein "o", der neue
  Admin kann sie wieder öffnen; k nie übertragen).
- Mitglieder sehen in offenen Gruppen den Link (zum Teilen) nur, wenn der Admin ihn ihnen gibt: der
  Admin schickt k beim Öffnen/Zurücksetzen/Beitritt an alle Mitglieder als
  `\1mesh:gk:<gid>|<k>` (nur vom aktuellen Admin annehmen, nur wenn Zustand "o":1; bei Schließen leer).
- Prüfvektoren: Link `meshg:1:0123456789abcdef:<64×a>:00112233445566778899aabbccddeeff` -> gid,
  Admin a…a, k. gj mit k: `\1mesh:gj:0123456789abcdef|QmVu|00112233445566778899aabbccddeeff` -> Name
  "Ben", k. Zustand mit o: wie B6 plus `,"o":1` nach "tm".
