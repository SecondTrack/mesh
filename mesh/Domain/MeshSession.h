// Einzige Schnittstelle der UI zur App: Entsperren, Kontakte, Nachrichten senden
// und empfangen. Dahinter liegen Vault, Store und Relays.
// Meldet Datenänderungen per NSNotification an die UI.
#import <Foundation/Foundation.h>
#import "MeshNotifications.h"
#import "MeshSafetyCode.h"   // MeshSafetyScan

@class MeshMessage, MeshProfile, MeshPayload, MeshIdentityInfo, MeshGroupInfo;

enum { MeshMaxFileBytes = 500 * 1024 };   // Datei als Ganzes in einer Nachricht (Android: 700 000 Base64-Zeichen)

typedef NS_ENUM(NSInteger, MeshPinResult) {
    MeshPinOK,
    MeshPinWrong,
    MeshPinLockedOut,        // zu viele Fehlversuche, siehe pinWaitRemaining
    MeshPinDeviceChanged,    // Schlüssel ist an ein anderes Gerät gebunden (Geheimnis sicher nicht vorhanden)
    MeshPinKeychainBusy,     // Schlüsselbund gerade nicht lesbar, später erneut versuchen
    MeshPinStorageUnreadable,// Datenbank nicht lesbar: kein Versuch wird gezählt
    MeshPinWiped,            // Panik-PIN oder zu viele Fehlversuche: alles gelöscht, neu einrichten
    MeshPinSameAsReal,       // Panik-PIN darf nicht die echte PIN sein
    MeshPinSameAsPanic,      // neue PIN darf nicht die Panik-PIN sein
    MeshPinFailed            // Schreiben fehlgeschlagen oder ungültige Eingabe
};

enum { MeshPinLength = 6 };

// Wie der Schlüssel geschützt ist; die Oberfläche nennt beides "Code".
typedef NS_ENUM(NSInteger, MeshSecretKind) {
    MeshSecretPin,     // 6 Ziffern, PBKDF2: schnell, gegen ausgelesene Geräte schwach
    MeshSecretWords    // 5 oder 6 gewürfelte Wörter, scrypt
};

@interface MeshSession : NSObject
+ (instancetype)shared;

@property (nonatomic, readonly) BOOL anyRelayConnected;
@property (nonatomic, readonly) NSUInteger connectedRelayCount;
@property (nonatomic, readonly) NSUInteger relayCount;
@property (nonatomic, readonly) BOOL unlocked;

- (void)start;                          // Store öffnen und Tor starten; der Schlüssel kommt erst beim Entsperren in den RAM
- (void)lock;                           // Schlüssel aus dem RAM entfernen

// Gesperrt im Hintergrund nur auf neue DMs lauschen (MeshIncomingMessageNotification ohne Inhalt)
// und die Notlöschung per Codewort ausführen. keepWatching aus dem VoIP-Weckruf.
- (void)startWatching;
- (void)stopWatching;
- (void)keepWatching;

- (NSString *)myPubkeyHex;
- (NSString *)myNpub;

// Mehrere Identitäten wie in der Android-App: alle mit derselben PIN, alle empfangen gleichzeitig,
// angezeigt wird eine. Der Umschalter steht hinter einer erneuten PIN-Abfrage.
- (int)activeIdentitySlot;          // ohne identities: die lädt (entschlüsselt) alle Profile
- (NSArray *)identities;                                      // MeshIdentityInfo
- (void)switchToIdentity:(int)slot;                           // MeshIdentityChangedNotification
- (BOOL)addIdentityWithPin:(NSString *)pin nsec:(NSString *)nsec;   // nsec nil = neuer Schlüssel; wird aktiv
@property (nonatomic) BOOL unifiedInbox;                      // Chats aller Identitäten in einer Liste

// Sicherheit: geheimen Schlüssel als nsec (nur im entsperrten Zustand).
- (NSString *)myNsec;                                      // nil wenn gesperrt

// Eigenes Profil (Name/Über/Bild). Speichern publiziert zusätzlich NIP-01-kind-0-Metadaten.
- (MeshProfile *)profile;
- (void)saveProfile:(MeshProfile *)profile;   // speichert und veröffentlicht Name/Beschreibung (kind 0)

// Transport: YES, wenn die Relays über Tor erreicht werden.
- (BOOL)usesTor;
- (BOOL)torReady;                 // Tor-Dienst verbunden: erst dann gehen Relays raus
- (BOOL)torFailed;                // Dienst seit Minuten nicht erreichbar
- (int)torBootstrapPercent;
- (BOOL)torFirstStart;            // Tor hat noch kein Netz-Verzeichnis: erster Start dauert deutlich länger
- (BOOL)clockPlausible;   // NO: Geräteuhr vor dem Build-Datum, Zertifikatsablauf nur grob prüfbar

- (void)setOpenChat:(NSString *)peerHex;   // sichtbarer Chat (nil = keiner): Neues gilt dort als gelesen
- (void)userDidInteract;                   // Berührung (App-Fenster): Hintergrundarbeit wie der Medien-Umzug wartet

@end

// PIN-Sperre und Notlöschung (MeshSession+Pin.m).
@interface MeshSession (Pin)
// PIN-Sperre: der Seckey liegt mit PIN verschlüsselt (PBKDF2+AES) im Vault.
- (BOOL)needsSetup;                     // noch kein Vault -> Code festlegen
+ (BOOL)isValidPin:(NSString *)pin;     // genau MeshPinLength Ziffern
+ (BOOL)isValidSecret:(NSString *)secret kind:(MeshSecretKind)kind;   // Wörter: alle aus der Liste, mindestens 5
- (MeshSecretKind)secretKind;           // auch gesperrt lesbar (Sperrbildschirm)
- (MeshPinResult)setupWithSecret:(NSString *)secret kind:(MeshSecretKind)kind;
- (MeshPinResult)setupWithPin:(NSString *)pin;   // Identität erzeugen/übernehmen, verschlüsseln, online gehen
- (MeshPinResult)unlockWithPin:(NSString *)pin;
- (NSTimeInterval)pinWaitRemaining;     // Sekunden bis zur nächsten erlaubten Eingabe
- (BOOL)keyBoundToDevice;               // Vault nutzt das Gerätegeheimnis aus dem Schlüsselbund
// Alles löschen (Schlüssel, Nachrichten, Kontakte, Gerätegeheimnis): für eine vergessene PIN oder
// einen Schlüssel, der an ein anderes Gerät gebunden ist. Danach: needsSetup == YES.
- (void)resetEverything;

// Notlöschung (siehe MeshPanic): Codewort, das Kontakte senden können, und Panik-PIN.
- (BOOL)hasPanicCodeword;
- (BOOL)panicCodewordNeedsRenewal;                          // gesetzt, aber eine neue Identität fehlt
- (BOOL)setPanicCodeword:(NSString *)codeword;              // leer = aus
- (BOOL)hasPanicPin;
- (MeshPinResult)setPanicPin:(NSString *)pin;               // MeshPinSameAsReal, wenn es die echte PIN ist
- (void)clearPanicPin;
- (BOOL)sendPanicTrigger:(NSString *)codeword to:(NSString *)peerHex;   // löscht das Gerät des Kontakts, wenn es passt
- (void)wipe;                                               // sofort alles löschen, MeshWipedNotification

// PIN prüfen/ändern
- (MeshPinResult)verifyPin:(NSString *)pin;                // gegen den Vault prüfen (ohne State-Änderung)
- (MeshPinResult)setNewPin:(NSString *)newPin;
- (MeshPinResult)setNewSecret:(NSString *)secret kind:(MeshSecretKind)kind;   // auch Wechsel PIN ↔ Wörter (Panik-PIN entfällt); entsperrt nötig

@end

// Kontakte, Chats und Nachrichten der angezeigten Identität (MeshSession+Chats.m).
@interface MeshSession (Chats)
// Kontakt hinzufügen (aus npub oder hex). Gibt den hex-Pubkey zurück, nil bei ungültig.
- (NSString *)addContact:(NSString *)npubOrHex name:(NSString *)name;
- (NSString *)pubkeyOfContactCode:(NSString *)code;          // Hex aus npub/Mesh-Code, nil wenn ungültig

// Kontakte und Chats: die UI greift nur hierüber auf den Store zu.
- (NSString *)displayNameFor:(NSString *)peerHex;          // gespeicherter Name, sonst Profilname, sonst gekürzter Key
- (NSString *)pictureFor:(NSString *)peerHex;
- (NSString *)aboutFor:(NSString *)peerHex;                // "Über mich" aus dem Profil (nil wenn keins oder nicht angenommen)              // Profilbild (nil wenn keins oder Kontakt nicht angenommen)
- (BOOL)isAccepted:(NSString *)peerHex;                    // selbst hinzugefügt, angeschrieben oder bestätigt
- (void)acceptContact:(NSString *)peerHex;                 // Bilder und Profilbild dieses Kontakts anzeigen
- (NSString *)npubFor:(NSString *)peerHex;
- (NSArray *)safetyNumberWith:(NSString *)peerHex;         // 12 Gruppen, auf beiden Seiten (auch Android) gleich; nil ohne Bundle
- (BOOL)usesSignalWith:(NSString *)peerHex;                // Signal-Sitzung steht (Forward Secrecy)
- (NSString *)myContactCode;                               // mesh:<npub>?sig=<Bundle mit frischem Einmal-Schlüssel>
- (NSString *)myStaticContactCode;                         // ohne Einmal-Schlüssel, zum Kopieren und Weitergeben
- (NSString *)safetyCodeQRWith:(NSString *)peerHex;        // Inhalt für den QR zum Scannen (MeshSafetyCode), nil ohne Bundle
- (MeshSafetyScan)checkSafetyScan:(NSString *)scanned with:(NSString *)peerHex;   // bei Übereinstimmung verifiziert
- (BOOL)isVerified:(NSString *)peerHex;
- (void)setVerified:(BOOL)verified for:(NSString *)peerHex;
- (NSArray *)chatList;                                     // NSArray<MeshChat>, neueste zuerst
- (NSArray *)messagesWith:(NSString *)peerHex;             // NSArray<MeshMessage>, älteste zuerst
- (NSArray *)messagesWith:(NSString *)peerHex limit:(NSUInteger)limit;   // nur die neuesten, älteste zuerst
- (NSArray *)messagesWith:(NSString *)peerHex before:(MeshMessage *)oldest limit:(NSUInteger)limit;   // die älteren davor, älteste zuerst
- (NSUInteger)messageCountFrom:(NSString *)key in:(NSString *)peerHex;   // so viele neueste laden, damit key dabei ist; 0 = weg
- (NSUInteger)messageCountAfter:(long long)ts in:(NSString *)peerHex;    // Nachrichten jünger als ts (ohne zu entschlüsseln)
- (BOOL)hasMessage:(NSString *)key in:(NSString *)peerHex;                // per cmid/Event-ID, ohne zu entschlüsseln
- (NSData *)mediaOf:(MeshMessage *)message;                // JPEG, AAC bzw. Datei, nil bei Text
- (MeshPayload *)payloadOf:(MeshMessage *)message;
- (NSArray *)mediaWith:(NSString *)peerHex;                // Bilder und Videos für die Galerie, neueste zuerst
- (NSUInteger)mediaCountWith:(NSString *)peerHex onlyMine:(BOOL)mine;   // Anzahl wie mediaWith + isVideo, ohne Zeilen zu laden
- (BOOL)isVideo:(MeshMessage *)message;                    // Datei ist ein MP4-Video (einmal geprüft, dann gemerkt)
- (long long)readAtIn:(NSString *)peerHex;                 // bis hier gelesen (Unix-Sekunden, 0 = unbekannt)
- (void)markReadIn:(NSString *)peerHex;                    // alles bis jetzt gelesen         // vollständig (Dateiname, Kontaktkarte)
- (MeshMessage *)message:(NSString *)key in:(NSString *)peerHex;   // per cmid/Event-ID, z.B. für Zitate
- (void)deleteMessage:(MeshMessage *)message;              // nur lokal
- (BOOL)deleteForEveryone:(MeshMessage *)message in:(NSString *)peerHex;   // nur eigene; auch beim Kontakt
- (void)react:(NSString *)emoji to:(MeshMessage *)message in:(NSString *)peerHex;   // gleiche nochmal = entfernen
- (void)clearChat:(NSString *)peerHex forEveryone:(BOOL)everyone;   // Kontakt bleibt
- (void)rememberImageWidth:(int)width height:(int)height of:(MeshMessage *)message;
- (void)deleteChat:(NSString *)peerHex;                    // Kontakt mit allen Nachrichten, nur lokal
- (void)blockContact:(NSString *)peerHex;                  // löschen, künftige Nachrichten ignorieren

// Selbstlöschende Nachrichten je Chat (gilt für beide Seiten): Sekunden, 0 = aus. fromSent: Uhr
// läuft ab dem Absenden, sonst ab dem Lesen.
- (int)timerFor:(NSString *)peerHex fromSent:(BOOL *)fromSent;
- (void)setTimer:(int)seconds fromSent:(BOOL)fromSent for:(NSString *)peerHex;

// Senden: verschlüsselt, signiert, an die Relays und lokal gespeichert. Format siehe MeshPayload.
// replyTo: cmid der zitierten Nachricht oder nil.
- (BOOL)sendTo:(NSString *)peerHex text:(NSString *)text replyTo:(NSString *)replyTo;
- (BOOL)sendImageTo:(NSString *)peerHex jpeg:(NSData *)jpeg replyTo:(NSString *)replyTo;
- (BOOL)sendVoiceTo:(NSString *)peerHex audio:(NSData *)audio seconds:(int)seconds replyTo:(NSString *)replyTo;   // AAC/m4a
- (BOOL)sendFileTo:(NSString *)peerHex data:(NSData *)data name:(NSString *)name mime:(NSString *)mime replyTo:(NSString *)replyTo;
- (BOOL)sendContact:(NSString *)contactHex to:(NSString *)peerHex;   // Kontaktkarte mit Name und Mesh-Code
// Gruppen: Bild höchstens 256 KB, Sprache höchstens 512 KB (Base64, B8.3). YES = dafür zu groß (Hinweis zeigen).
- (BOOL)tooLargeForGroup:(NSString *)chat image:(NSData *)jpeg;
- (BOOL)tooLargeForGroup:(NSString *)chat voice:(NSData *)audio seconds:(int)seconds;
- (NSArray *)acceptedContacts;                                       // Hex-Pubkeys, z.B. zum Teilen
- (NSString *)senderName:(NSString *)pubkey inChat:(NSString *)chat; // Gruppe: Kontaktname, sonst Name aus der Gruppe
@end

// Gruppen und Team-Chat (MeshSession+Groups.m, docs/TEAM_GROUPS_PROTOCOL.md). Chat-Schlüssel wie in
// MeshChat.h: "g:<gid>" bzw. "team"; die Chat-Methoden oben nehmen sie wie einen Kontakt.
@interface MeshSession (Groups)
- (BOOL)isGroupChat:(NSString *)chat;
- (BOOL)isTeamChat:(NSString *)chat;
- (NSString *)createGroupNamed:(NSString *)name members:(NSArray *)pubkeys;   // Chat-Schlüssel, nil bei Fehler
- (MeshGroupInfo *)groupInfo:(NSString *)chat;                               // nil = keine (bekannte) Gruppe
- (BOOL)acceptGroupInvite:(NSString *)chat;
- (void)declineGroupInvite:(NSString *)chat;
- (BOOL)leaveGroup:(NSString *)chat;                                         // Admin: auflösen
- (BOOL)deletingDissolvesGroup:(NSString *)chat;                             // Admin einer aktiven Gruppe: "Chat löschen" löst für alle auf (B8.8)
- (BOOL)inviteContacts:(NSArray *)pubkeys toGroup:(NSString *)chat;          // nur Admin; auch "Erneut einladen" (B8.5)
- (BOOL)removeMember:(NSString *)pubkey fromGroup:(NSString *)chat;          // nur Admin
- (BOOL)renameGroup:(NSString *)chat to:(NSString *)name;                    // nur Admin
- (BOOL)setGroupPicture:(NSData *)jpeg chat:(NSString *)chat;              // nur Admin; nil = entfernen (B7)
// B9: Admin übergeben (leave: danach austreten), Kontakt vorschlagen, Vorschläge annehmen/ablehnen.
- (BOOL)transferAdmin:(NSString *)pubkey inGroup:(NSString *)chat leave:(BOOL)leave;
- (BOOL)proposeContact:(NSString *)pubkey toGroup:(NSString *)chat;
- (NSArray *)proposableContacts:(NSString *)chat;                            // eigene angenommene Kontakte, nicht in m
- (BOOL)acceptProposal:(long long)proposalId inGroup:(NSString *)chat;
- (BOOL)rejectProposal:(long long)proposalId inGroup:(NSString *)chat;
// B10: offen/geschlossen, Link zurücksetzen, Link als Karte senden (nur 1:1), Beitreten per Link.
- (BOOL)setGroupOpen:(BOOL)open chat:(NSString *)chat;
- (BOOL)resetGroupLink:(NSString *)chat;
- (BOOL)sendGroupLink:(NSString *)chat to:(NSString *)peerHex;
// Text (gescannt, eingefügt, aus einer Karte) als Beitritts-Link: @{link, chat, admin, adminLabel}; nil = keiner.
- (NSDictionary *)groupLinkDetails:(NSString *)text;
- (NSString *)joinGroupByLink:(NSString *)link name:(NSString *)groupName;   // Chat-Schlüssel, nil = abgelehnt

// Team-Chat der angezeigten Identität
- (BOOL)teamChatAvailable;      // Team-Chat an (echter TEAM_PK, nicht selbst das Team)
- (BOOL)teamCanSend;            // getrennte Verbindung (Tor) vorhanden
@property (nonatomic) BOOL teamChatHidden, teamChatMuted;
- (void)startTeamChatOver;      // persönliche Nachrichten löschen, neuer Einweg-Schlüssel
@end

@interface MeshSession (Pairing)
// Kontakt per 4 Wörtern (ohne Kamera): Wörter erzeugen (10 Minuten gültig) bzw. eingetippte einlösen
- (void)pairingWords:(void (^)(NSString *words, NSDate *expires, NSString *error))done;
- (void)addContactByWords:(NSString *)words name:(NSString *)name done:(void (^)(NSString *hex, NSString *error))done;
+ (BOOL)looksLikePairingWords:(NSString *)text;
@end
