// Der entschlüsselte Inhalt einer Mesh-DM, Format der Android-App (MeshNostr.kt):
//
//   [\1mesh:x:<cmid>[|r=<cmid>][|t=<s>|tr=<s>]\n]   Kopf einer Nachricht: ID, Antwort auf, Selbstlöschen
//   [\1mesh:mb:<bundle>\n] [mesh:on:<onion>\n]        Signal-Bundle und .onion des Absenders (die .onion
//                                                     braucht nur Androids Tor-Zustellung; sie wird verworfen)
//   <Inhalt>                                          Text oder MeshPayload (Bild, Sprache, Datei)
//
// Statt einer Nachricht kann der Inhalt auch eine Steueranweisung sein, die nie als Nachricht
// erscheint: Reaktion (\1mesh:rx:<ziel>|<emoji>), Löschen für alle (\1mesh:del:<ziel>), Chat leeren
// (\1mesh:clr:), Selbstlösch-Timer (\1mesh:ttls:<s>|<read|sent>), Handshake (mesh:hi:), Profilbild
// (\1mesh:pic:<Base64-JPEG>; Android veröffentlicht sein Bild nicht auf Relays) und Teile
// großer Dateien (\1mesh:fc:…). <ziel> ist die cmid einer Nachricht, bei alten die Event-ID.
// Nur diese Klasse kennt die Marker.
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, MeshEnvelopeType) {
    MeshEnvelopeMessage,
    MeshEnvelopeReaction,
    MeshEnvelopeDelete,
    MeshEnvelopeClear,
    MeshEnvelopeTimer,
    MeshEnvelopeHello,
    MeshEnvelopeFileChunk,
    MeshEnvelopePicture,       // privates Profilbild (\1mesh:pic:<Base64-JPEG>), leer = entfernt
    MeshEnvelopeIgnored        // leer oder ein Steuermarker im Text: nicht anzeigen
};

typedef NS_ENUM(NSInteger, MeshTimerMode) {
    MeshTimerFromRead,         // "Ab Gesehen": Uhr startet, wenn der Empfänger den Chat öffnet
    MeshTimerFromSent          // "Ab Gesendet": Uhr läuft ab dem Absenden
};

@interface MeshEnvelope : NSObject
+ (instancetype)parse:(NSString *)plain;

@property (nonatomic, readonly) MeshEnvelopeType type;
@property (nonatomic, readonly) NSString *bundle;      // Signal-Bundle des Absenders, falls mitgeschickt

// MeshEnvelopeMessage
@property (nonatomic, readonly) NSString *content;     // Text oder MeshPayload-Inhalt
@property (nonatomic, readonly) NSString *cmid;        // stabile Nachrichten-ID des Absenders, @"" bei alten
@property (nonatomic, readonly) NSString *replyTo;     // cmid der zitierten Nachricht, @"" = keine
// MeshEnvelopeMessage und MeshEnvelopeTimer: Selbstlöschen in Sekunden (0 = aus) und ab wann.
@property (nonatomic, readonly) int timer;
@property (nonatomic, readonly) MeshTimerMode timerMode;

// MeshEnvelopeReaction und MeshEnvelopeDelete
@property (nonatomic, readonly) NSString *target;
@property (nonatomic, readonly) NSString *emoji;       // @"" = Reaktion entfernt

// MeshEnvelopePicture: Base64 des Bildes, @"" = Bild entfernt (Prüfung macht der Empfänger)
@property (nonatomic, readonly) NSString *picture;

// MeshEnvelopeFileChunk
@property (nonatomic, readonly) NSString *fileId;      // 16 Hex-Zeichen
@property (nonatomic, readonly) int chunkIndex, chunkCount;
@property (nonatomic, readonly) NSString *fileName, *fileMime;
@property (nonatomic, readonly) NSString *thumbnail;   // Base64-JPEG, nur im ersten Teil
@property (nonatomic, readonly) NSString *chunk;       // Base64 der Bytes dieses Teils

// Zum Senden. bundle (optional) reist vor dem Inhalt mit, damit die Gegenseite Signal aufbauen kann.
// Steueranweisungen nie mit Bundle: Android prüft sie vor dem Abstreifen und zeigte sie sonst nicht an.
+ (NSString *)message:(NSString *)content cmid:(NSString *)cmid replyTo:(NSString *)replyTo
                timer:(int)seconds mode:(MeshTimerMode)mode bundle:(NSString *)bundle;
+ (NSString *)reactionTo:(NSString *)target emoji:(NSString *)emoji;
+ (NSString *)deletionOf:(NSString *)target;
+ (NSString *)clearChat;
+ (NSString *)timer:(int)seconds mode:(MeshTimerMode)mode;
+ (NSString *)helloWithBundle:(NSString *)bundle;
+ (NSString *)picture:(NSString *)base64;   // eigenes Profilbild an einen Kontakt, @"" = entfernt

+ (NSString *)newMessageId;   // 16 Hex-Zeichen (8 Zufallsbytes) wie Android
@end
