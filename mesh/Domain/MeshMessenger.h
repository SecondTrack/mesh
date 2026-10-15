// Nachrichten im Format der Android-App senden und empfangen (siehe MeshEnvelope): Text und
// Medien mit Nachrichten-ID, Antworten, Reaktionen, Löschen für alle, Chat leeren und
// selbstlöschende Nachrichten. Verschlüsselt mit Signal, sobald das Bundle des Kontakts bekannt
// ist, sonst NIP-44 (zu Großes NIP-04); jede Nachricht trägt das eigene Bundle mit, damit die
// Gegenseite auf Signal wechseln kann (wie MeshNostr.encryptFor).
// Gibt es nur im entsperrten Zustand (hält den Schlüssel); MeshSession erzeugt und verwirft ihn.
#import <Foundation/Foundation.h>
#import "MeshChat.h"   // MeshGroupStatus
@class MeshStore, MeshKeys, MeshEvent, MeshMessage, MeshInboxPolicy, MeshPanic, MeshSignal, MeshMessenger, MeshGroupState;

@protocol MeshMessengerDelegate <NSObject>
- (void)messenger:(MeshMessenger *)messenger send:(MeshEvent *)event;      // in die Warteschlange und an die Relays
- (void)messenger:(MeshMessenger *)messenger acceptedContact:(NSString *)peer;
- (void)messengerReceivedPanic:(MeshMessenger *)messenger;                  // Codewort: alles löschen
- (void)messenger:(MeshMessenger *)messenger received:(MeshMessage *)message from:(NSString *)peer;
@optional
- (void)messenger:(MeshMessenger *)messenger changedPictureOf:(NSString *)peer;   // privat geschicktes Profilbild übernommen
@end

@interface MeshMessenger : NSObject
- (instancetype)initWithStore:(MeshStore *)store keys:(MeshKeys *)keys inbox:(MeshInboxPolicy *)inbox panic:(MeshPanic *)panic;
@property (nonatomic, mesh_weak) id<MeshMessengerDelegate> delegate;
@property (nonatomic, copy) NSString *openChat;   // gerade sichtbarer Chat: dort gilt Neues als gelesen
@property (nonatomic, readonly) NSString *myPubkey;
@property (nonatomic) MeshSignal *signal;         // nil: nur NIP-44/NIP-04

// Senden. content im Format von MeshPayload; replyTo = cmid der zitierten Nachricht oder nil.
- (MeshMessage *)send:(NSString *)content to:(NSString *)peer replyTo:(NSString *)replyTo;
- (BOOL)react:(NSString *)emoji to:(MeshMessage *)message in:(NSString *)peer;   // gleiche Reaktion nochmal = entfernen
- (BOOL)deleteForEveryone:(MeshMessage *)message in:(NSString *)peer;           // nur eigene Nachrichten
- (void)clearChat:(NSString *)peer forEveryone:(BOOL)everyone;
- (void)setTimer:(int)seconds fromSent:(BOOL)fromSent for:(NSString *)peer;
- (int)timerFor:(NSString *)peer fromSent:(BOOL *)fromSent;
- (BOOL)sendPanicTrigger:(NSString *)codeword to:(NSString *)peer;   // nur das Token reist, nie das Codewort
- (BOOL)sayHelloTo:(NSString *)peer;   // unsichtbarer Handshake nach dem Hinzufügen: eigenes Bundle
// Eigenes Profilbild privat (verschlüsselte Steueranweisung, wie Android): nach dem Hinzufügen und Annehmen
// an den Kontakt; nach einer Änderung an alle angenommenen Kontakte (dann auch "entfernt").
- (BOOL)sendPictureTo:(NSString *)peer;          // nichts, wenn kein eigenes Bild
- (void)sendPictureToAllContacts;

- (void)chatOpened:(NSString *)peer;    // Uhren empfangener Nachrichten starten
- (BOOL)deleteExpired;                  // YES, wenn etwas gelöscht wurde
- (NSTimeInterval)secondsUntilNextExpiry;   // < 0: keine Uhr läuft

// Empfangen: ein kind-4-Event. YES, wenn sich etwas Sichtbares geändert hat.
- (BOOL)receive:(MeshEvent *)event;

- (void)finishPendingSends;   // ausstehende Fan-out-Kopien jetzt bauen und senden (vor dem Sperren)
- (void)wipeKeys;   // zwischengespeicherte Schlüssel je Kontakt überschreiben (beim Sperren)
@end

// Gruppen (docs/TEAM_GROUPS_PROTOCOL.md, Teil B; MeshMessenger+Groups.m). Fan-out: jede Nachricht geht
// einzeln über den 1:1-Weg an jedes Mitglied; Nicht-Kontakte bekommen nie ein Bundle. Der Admin
// führt den Zustand (Revision), alle anderen übernehmen nur Neueres von ihm.
@interface MeshMessenger (Groups)
// Neue Gruppe mit mir als Admin; an members (angenommene Kontakte, höchstens 19) gehen sofort Einladungen.
- (NSString *)createGroup:(NSString *)name members:(NSArray *)pubkeys myName:(NSString *)myName;   // gid, nil bei Fehler
- (MeshGroupState *)groupState:(NSString *)gid status:(MeshGroupStatus *)status inviter:(NSString **)inviter;
- (NSArray *)pendingInvitesForGroup:(NSString *)gid;   // nur Admin, höchstens 30 Tage alt
- (MeshMessage *)sendGroup:(NSString *)gid content:(NSString *)content replyTo:(NSString *)replyTo;
- (BOOL)reactInGroup:(NSString *)gid emoji:(NSString *)emoji to:(MeshMessage *)message;
- (BOOL)deleteInGroup:(NSString *)gid message:(MeshMessage *)message;   // nur eigene, bei allen
- (BOOL)acceptInvite:(NSString *)gid myName:(NSString *)myName;
- (void)declineInvite:(NSString *)gid;                                    // nichts senden (unsichtbar)
- (BOOL)leaveGroup:(NSString *)gid;                                       // Admin: Gruppe auflösen (gs m=[] und gl, B8.7)
- (BOOL)deletingDissolves:(NSString *)gid;                                // Admin einer aktiven Gruppe: Löschen löst für alle auf (B8.8)
- (BOOL)deleteGroup:(NSString *)gid;                                      // erst verlassen, dann lokal alles weg
// Kontakt wurde angenommen (Nutzer oder Antwort): zurückgehaltene Einladungen von ihm prüfen (B8.5).
- (BOOL)contactAccepted:(NSString *)peer;
// Nach dem Entsperren: offene Einladungen (Admin) und zurückgehaltene nach 30 Tagen vergessen,
// zurückgehaltene von inzwischen angenommenen Kontakten zeigen. YES = Chatliste geändert.
- (BOOL)maintainGroups;
+ (BOOL)fitsGroup:(NSString *)content;   // B8.2/B8.3: Art und Größe in Gruppen erlaubt (Bild ≤ 256 KB, Sprache ≤ 512 KB)
// Nur Admin. Einladen (auch erneut) erhöht immer die Revision (B8.1).
- (BOOL)invite:(NSArray *)pubkeys toGroup:(NSString *)gid;
- (BOOL)removeMember:(NSString *)pubkey fromGroup:(NSString *)gid;
- (BOOL)renameGroup:(NSString *)gid to:(NSString *)name;
- (BOOL)setGroupTimer:(int)seconds fromSent:(BOOL)fromSent group:(NSString *)gid;
// Gruppenbild (B7): JPEG/PNG bis 64 KB; nil = entfernen. Neues Bild: r+1, Zustand an alle, Bild an jedes Mitglied.
- (BOOL)setGroupPicture:(NSData *)bytes group:(NSString *)gid;
// Alle: Base64 des Gruppenbilds, nur beigetreten und passend zum p des Zustands; nil = Identicon.
- (NSString *)groupPicture:(NSString *)gid;
+ (NSString *)groupPictureHash:(NSData *)bytes;   // p: erste 16 Hex von SHA-256
@end

// Nachträge B9 (Admin übergeben, Vorschläge) und B10 (offene Gruppen, Beitritts-Link); MeshMessenger+GroupsOpen.m.
@interface MeshMessenger (GroupsOpen)
// Nur Admin: an ein Mitglied übergeben (r+1, schließt die Gruppe). leave: danach austreten; gl an jeden erst,
// wenn ein Relay seinen Übergabe-Zustand bestätigt hat (eventStored:).
- (BOOL)transferAdmin:(NSString *)pubkey group:(NSString *)gid leave:(BOOL)leave;
- (BOOL)eventStored:(NSString *)eventId;   // ein Relay hat ein eigenes Event bestätigt: Aufgeschobenes senden
// Mitglied: eigenen angenommenen Kontakt vorschlagen (gvo an ihn, gpr an den Admin). name: eigener Kontaktname.
- (BOOL)proposeContact:(NSString *)pubkey name:(NSString *)name group:(NSString *)gid;
// Admin: offene Vorschläge, je @{id, from, candidate, name}; Einladen (normale Einladung, B8.1) oder still ablehnen.
- (NSArray *)proposalsForGroup:(NSString *)gid;
- (BOOL)acceptProposal:(long long)proposalId group:(NSString *)gid;
- (BOOL)rejectProposal:(long long)proposalId group:(NSString *)gid;
// Einladung von einem Admin, der kein Kontakt ist: der Bürge (angenommener Kontakt) oder nil.
- (NSString *)voucherForInvite:(NSString *)gid;
// Admin: offen (neues k, r+1, gk an alle) bzw. geschlossen (r+1, gk leer); Link zurücksetzen (neues k, r+1).
- (BOOL)setGroupOpen:(BOOL)open group:(NSString *)gid;
- (BOOL)resetGroupLink:(NSString *)gid;
- (NSString *)groupLink:(NSString *)gid;   // meshg:1:… (Admin oder Mitglied mit k), nil = keiner
// Beitreten per Link: Platzhalter-Eintrag ("tritt bei") und gj mit k an den Admin. gid, nil = abgelehnt.
- (NSString *)joinGroupByLink:(NSString *)link name:(NSString *)groupName myName:(NSString *)myName;
@end
