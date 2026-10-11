// Eine Nachricht in einer Konversation (aus sqlite).
// Bei Bild-, Sprach- und Dateinachrichten enthält content nur den Marker (siehe MeshPayload);
// die Nutzdaten lädt erst -[MeshSession mediaOf:], damit lange Chats wenig RAM brauchen.
#import <Foundation/Foundation.h>
#import "MeshPayload.h"

typedef NS_ENUM(NSInteger, MeshMessageStatus) {
    MeshMessageSending   = 0,   // gespeichert, wartet auf die Bestätigung eines Relays
    MeshMessageDelivered = 1,   // ein Relay, an das sie ging, hat sie angenommen
    MeshMessageFailed    = 2    // innerhalb der Frist von keinem Relay angenommen
};

@interface MeshMessage : NSObject
@property (nonatomic, assign) long long rowId;
@property (nonatomic, assign) MeshPayloadKind kind;
@property (nonatomic, copy)   NSString *content;
@property (nonatomic, assign) BOOL      fromMe;
@property (nonatomic, assign) long long ts;        // Unix-Sekunden
@property (nonatomic, copy)   NSString *eventId;
@property (nonatomic, assign) MeshMessageStatus status;
@property (nonatomic, assign) int width, height;   // Bildmaße, 0 = noch nicht bekannt
@property (nonatomic, copy)   NSString *cmid;      // Nachrichten-ID des Absenders (Antworten, Reaktionen)
@property (nonatomic, copy)   NSString *replyTo;   // cmid der zitierten Nachricht
@property (nonatomic, copy)   NSString *reactMine, *reactPeer;   // je ein Emoji oder nil
@property (nonatomic, assign) int timer;           // Selbstlöschen nach so vielen Sekunden, 0 = nie
@property (nonatomic, assign) long long expiresAt; // Unix-Sekunden; 0 = Uhr läuft noch nicht

- (NSString *)key;   // Ziel für Reaktionen und Löschen: cmid, bei alten Nachrichten die Event-ID
@end
