// Inhalt einer Nachricht. Über Nostr geht nur Text; Medien stecken als Base64 mit Marker darin,
// im Format der Android-App:
//
//   mesh:img<base64 JPEG>
//   mesh:voc:<Sekunden>|<base64 AAC>
//   \1mesh:file:<Name>\1<MIME>\n<base64>
//   mesh:contact:<Name>\n<Mesh-Code>           Kontaktkarte
//
// Ältere iPod-Versionen schrieben "mesh:img:<b64>" und "mesh:voice:<s>:<b64>"; beides wird weiter
// gelesen. Hinweise im Verlauf sind lokale Zeilen: "ttl:<s>:<1|0>" (Selbstlöschen geändert) und
// "key:changed" (neuer Schlüssel des Kontakts).
// Nur diese Klasse kennt das Format. Das Dekodieren der Nutzdaten passiert erst bei -data.
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, MeshPayloadKind) {   // Werte stehen in der Datenbank (messages.kind)
    MeshPayloadText    = 0,
    MeshPayloadImage   = 1,
    MeshPayloadVoice   = 2,
    MeshPayloadFile    = 3,
    MeshPayloadNotice  = 4,   // lokal, wird nie gesendet
    MeshPayloadContact = 5
};

@interface MeshPayload : NSObject
+ (MeshPayloadKind)kindOf:(NSString *)content;            // schnell, schaut nur auf den Marker
+ (instancetype)parse:(NSString *)content;
+ (instancetype)parseNotice:(NSString *)content;          // nur für Zeilen mit kind = MeshPayloadNotice

// Nur der Marker (ohne Daten), z.B. für Listen; Text: nil.
+ (NSString *)markerForKind:(MeshPayloadKind)kind seconds:(int)seconds;

+ (NSString *)contentWithImage:(NSData *)jpeg;
+ (NSString *)contentWithVoice:(NSData *)audio seconds:(int)seconds;
+ (NSString *)contentWithFile:(NSData *)data name:(NSString *)name mime:(NSString *)mime;
+ (NSString *)contentWithContactName:(NSString *)name code:(NSString *)code;
+ (NSString *)noticeTimer:(int)seconds byMe:(BOOL)byMe;
+ (NSString *)noticeKeyChanged;                           // Signal-Identität des Kontakts ist neu

@property (nonatomic, readonly) MeshPayloadKind kind;
@property (nonatomic, readonly) NSString *text;           // Text; bei Kontaktkarten der Name
@property (nonatomic, readonly) int seconds;              // Sprache: Länge; Hinweis: Timer
@property (nonatomic, readonly) NSString *fileName, *fileMime;   // Datei
@property (nonatomic, readonly) NSString *code;           // Kontaktkarte: Mesh-Code
@property (nonatomic, readonly) BOOL byMe;                // Hinweis: selbst ausgelöst
@property (nonatomic, readonly) BOOL keyChanged;          // Hinweis: Schlüsselwechsel statt Timer
- (NSData *)data;                                         // JPEG, AAC bzw. Datei; nil ohne Daten
@end
