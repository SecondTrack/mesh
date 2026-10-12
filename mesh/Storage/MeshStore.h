// Persistenz über sqlite3 (System-Lib): Profil, Kontakte, Nachrichten; Vault in MeshStore+Vault.
// Nachrichteninhalte, Kontaktnamen, Profile und Bilder liegen verschlüsselt (MeshSeal) mit einem
// Datenschlüssel, den die Session nur im entsperrten Zustand setzt. Ohne Schlüssel werden diese
// Felder weder geschrieben noch gelesen. Unverschlüsselt: Pubkeys, Zeiten, Art/Länge von Medien.
#import <Foundation/Foundation.h>
@class MeshChat, MeshMessage, MeshProfile;

@interface MeshStore : NSObject
- (BOOL)openAtPath:(NSString *)path;     // legt die Datei an + Schema (MeshIdentity wählt den Pfad)
- (BOOL)destroyAndReopen;               // alles löschen, leer neu anlegen
- (void)setDataKey:(NSData *)key;        // 32 Byte; nil = gesperrt. Verschlüsselt dabei Altbestände.
// knownSealed: von außerhalb der Datei bekannt, dass sie schon versiegelt war (Schlüsselbund):
// dann gilt nur noch enc2, auch wenn user_version in der Datei zurückgesetzt wurde.
- (void)setDataKey:(NSData *)key knownSealed:(BOOL)knownSealed;
@property (nonatomic, readonly) BOOL sealed;

// Eigenes Profil
- (MeshProfile *)loadProfile;
- (BOOL)saveProfile:(MeshProfile *)profile;

// Kontakte
- (void)upsertContact:(NSString *)pubkeyHex name:(NSString *)name accepted:(BOOL)accepted;
- (void)setAccepted:(NSString *)pubkeyHex;            // vom Nutzer angenommen (hinzugefügt/angeschrieben/bestätigt)
- (BOOL)isAccepted:(NSString *)pubkeyHex;
- (int)unacceptedContactCount;
- (long long)unacceptedBytes;                          // Summe aller Nachrichten nicht angenommener Kontakte
- (NSString *)oldestUnacceptedContact;
- (BOOL)deleteContact:(NSString *)pubkeyHex;           // mit allen Nachrichten (+ Tombstones), alles oder nichts
- (void)blockContact:(NSString *)pubkeyHex;            // löschen und künftig ignorieren
- (BOOL)isBlocked:(NSString *)pubkeyHex;
- (void)unblockContact:(NSString *)pubkeyHex;
- (void)pruneTombstonesKeeping:(int)count;            // älteste Löschmerker verwerfen
- (int)receivedCount:(NSString *)pubkeyHex bytes:(long long *)bytes;   // empfangene Nachrichten eines Kontakts
- (NSArray *)acceptedContactPubkeys;
- (NSArray *)requestPubkeys:(NSUInteger)limit;   // nicht angenommene Absender, neueste Nachricht zuerst
- (BOOL)isDeleted:(NSString *)eventId;                // vom Nutzer gelöscht?
- (NSString *)nameForContact:(NSString *)pubkeyHex;   // nil = unbekannt
- (NSString *)picForContact:(NSString *)pubkeyHex;    // kind-0 "picture" (URL oder data:-URI), nil = keins
- (void)setVerified:(NSString *)pubkeyHex verified:(BOOL)v;
- (BOOL)isVerified:(NSString *)pubkeyHex;
// Profil eines Kontakts aus kind-0 (Name, Bild). Den Anzeigenamen bildet MeshSession.
- (void)forgetProfileTimeOf:(NSString *)pubkeyHex;   // nächstes Profil gilt als neuer (nach dem Annehmen)
- (BOOL)setContactProfile:(NSString *)pubkeyHex pname:(NSString *)pname pic:(NSString *)pic createdAt:(long long)ts;   // nur wenn neuer
- (BOOL)setContactProfile:(NSString *)pubkeyHex pname:(NSString *)pname pic:(NSString *)pic createdAt:(long long)ts sameAgain:(BOOL)same;   // same: auch bei gleichem Zeitstempel
- (NSString *)profileNameForContact:(NSString *)pubkeyHex;   // aus kind-0, nil = keiner
- (BOOL)isContact:(NSString *)pubkeyHex;

// Nachrichten
// Mit allen Feldern aus message (ohne rowId, content, Reaktionen); setzt rowId und kind. 0 = nicht eingefügt.
- (long long)insertMessage:(MeshMessage *)message chat:(NSString *)chat content:(NSString *)content;
- (MeshMessage *)messageWithKey:(NSString *)key chat:(NSString *)chat;   // per cmid oder Event-ID
- (void)deleteMessage:(long long)rowId;               // eine Nachricht löschen (+ Tombstone)
- (BOOL)hasEventId:(NSString *)eventId;
- (long long)newestReceivedTime;                       // 0 = noch nichts empfangen
- (void)setImageWidth:(int)width height:(int)height ofMessage:(long long)rowId;   // aus dem Dateikopf, für Zeilenhöhen
- (BOOL)markDelivered:(NSString *)eventId;   // Relay-OK → status=1, startet "Ab Gesehen"-Uhren (YES = Status geändert)
- (NSArray *)messagesForChat:(NSString *)pubkeyHex;   // MeshMessage*, aufsteigend nach ts
- (NSString *)contentOfMessage:(long long)rowId;          // vollständiger Inhalt (inkl. Medien)
- (NSArray *)chatList;                                 // MeshChat*, letzte Nachricht je Kontakt
@end
