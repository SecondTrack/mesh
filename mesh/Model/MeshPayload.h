// Inhalt einer Nachricht. Über Nostr geht nur Text; Medien stecken als Base64 mit Marker darin,
// im Format der Android-App:
//
//   mesh:img<base64 JPEG>
//   mesh:voc:<Sekunden>|<base64 AAC>
//   \1mesh:file:<Name>\1<MIME>\n<base64>
//   mesh:contact:<Name>\n<Mesh-Code>           Kontaktkarte
//   \1mesh:glink:<Base64 Gruppenname>\n<Link>  Link-Karte einer offenen Gruppe (B10, nur 1:1)
//
// Ältere iPod-Versionen schrieben "mesh:img:<b64>" und "mesh:voice:<s>:<b64>"; beides wird weiter
// gelesen. Hinweise im Verlauf sind lokale Zeilen: "ttl:<s>:<1|0>" (Selbstlöschen geändert),
// "key:changed" (neuer Schlüssel des Kontakts) und "grp:<Ereignis>:<Base64 Name>" (Gruppen).
// Nur diese Klasse kennt das Format. Das Dekodieren der Nutzdaten passiert erst bei -data.
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, MeshPayloadKind) {   // Werte stehen in der Datenbank (messages.kind)
    MeshPayloadText    = 0,
    MeshPayloadImage   = 1,
    MeshPayloadVoice   = 2,
    MeshPayloadFile    = 3,
    MeshPayloadNotice  = 4,   // lokal, wird nie gesendet
    MeshPayloadContact = 5,
    MeshPayloadGroupLink = 6  // text = Gruppenname (@"" = keiner, nil = nicht lesbar), code = Link (ungeprüft)
};

typedef NS_ENUM(NSInteger, MeshGroupNotice) {   // Systemzeilen im Gruppenchat
    MeshGroupNoticeNone = 0,
    MeshGroupNoticeJoined,       // name ist beigetreten
    MeshGroupNoticeLeft,         // name hat verlassen
    MeshGroupNoticeRemoved,      // name wurde entfernt
    MeshGroupNoticeRenamed,      // Gruppe heißt jetzt name
    MeshGroupNoticeYouRemoved,   // ich bin nicht mehr in der Gruppe
    MeshGroupNoticeDissolved,    // Gruppe aufgelöst
    MeshGroupNoticeYouLeft,
    MeshGroupNoticeCreated,      // name = Gruppenname
    MeshGroupNoticeNewAdmin,     // name ist jetzt Admin (B9)
    MeshGroupNoticeYouAdmin,     // ich bin jetzt Admin
    MeshGroupNoticeInviteExpired,   // Einladung abgelaufen (Admin gewechselt)
    MeshGroupNoticeProposed,     // ich habe name vorgeschlagen
    MeshGroupNoticeOpened,       // Gruppe ist jetzt offen (B10)
    MeshGroupNoticeClosed,       // Gruppe ist nicht mehr offen
    MeshGroupNoticeLast = MeshGroupNoticeClosed
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
+ (NSString *)contentWithGroupLinkName:(NSString *)name link:(NSString *)link;
+ (NSString *)noticeTimer:(int)seconds byMe:(BOOL)byMe;
+ (NSString *)noticeKeyChanged;                           // Signal-Identität des Kontakts ist neu
+ (NSString *)noticeGroup:(MeshGroupNotice)event name:(NSString *)name;

@property (nonatomic, readonly) MeshPayloadKind kind;
@property (nonatomic, readonly) NSString *text;           // Text; bei Kontaktkarten der Name
@property (nonatomic, readonly) int seconds;              // Sprache: Länge; Hinweis: Timer
@property (nonatomic, readonly) NSString *fileName, *fileMime;   // Datei
@property (nonatomic, readonly) NSString *code;           // Kontaktkarte: Mesh-Code; Link-Karte: Link
@property (nonatomic, readonly) BOOL byMe;                // Hinweis: selbst ausgelöst
@property (nonatomic, readonly) BOOL keyChanged;          // Hinweis: Schlüsselwechsel statt Timer
@property (nonatomic, readonly) MeshGroupNotice groupNotice;   // Hinweis: Gruppenereignis, Name in text
- (NSData *)data;                                         // JPEG, AAC bzw. Datei; nil ohne Daten
@end
