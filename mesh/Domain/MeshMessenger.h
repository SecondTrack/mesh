// Nachrichten im Format der Android-App senden und empfangen (siehe MeshEnvelope): Text und
// Medien mit Nachrichten-ID, Antworten, Reaktionen, Löschen für alle, Chat leeren und
// selbstlöschende Nachrichten. Verschlüsselt mit Signal, sobald das Bundle des Kontakts bekannt
// ist, sonst NIP-44 (zu Großes NIP-04); jede Nachricht trägt das eigene Bundle mit, damit die
// Gegenseite auf Signal wechseln kann (wie MeshNostr.encryptFor).
// Gibt es nur im entsperrten Zustand (hält den Schlüssel); MeshSession erzeugt und verwirft ihn.
#import <Foundation/Foundation.h>
@class MeshStore, MeshKeys, MeshEvent, MeshMessage, MeshInboxPolicy, MeshPanic, MeshSignal, MeshMessenger;

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

- (void)wipeKeys;   // zwischengespeicherte Schlüssel je Kontakt überschreiben (beim Sperren)
@end
