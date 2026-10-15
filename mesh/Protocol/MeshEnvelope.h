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
//
// Gruppen (docs/TEAM_GROUPS_PROTOCOL.md, Teil B): Kopfzeile \1mesh:g:<gid>\n vor Nachricht, Reaktion
// oder Löschen; Steueranweisungen Einladung (\1mesh:gi:<B64 Zustand>), Beitreten
// (\1mesh:gj:<gid>|<B64 Name>), Zustand (\1mesh:gs:<B64 Zustand>), Verlassen (\1mesh:gl:<gid>) und
// Gruppenbild (\1mesh:gp:<gid>|<B64 Bildbytes>, B7; Format und Hash prüft der Empfänger).
// B9/B10: Beitreten per Link (\1mesh:gj:<gid>|<B64 Name>|<k>), Vorschlag an den Admin
// (\1mesh:gpr:<gid>|<C-pk>|<B64 Name>), Bürgschaft an C (\1mesh:gvo:<gid>|<Admin-pk>|<B64 Gruppenname>),
// Link-Geheimnis an Mitglieder (\1mesh:gk:<gid>|<k oder leer>). Als Nachricht zusätzlich die Link-Karte
// (\1mesh:glink:<B64 Gruppenname>\n<Link>), Inhalt wie eine Kontaktkarte (MeshPayload).
// Team-Chat (Teil A3): Kopfzeile \1mesh:anon:1\n vor einer Textnachricht.
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
    MeshEnvelopeGroupInvite,   // groupState: Zustand-JSON aus der Einladung
    MeshEnvelopeGroupJoin,     // group + joinName
    MeshEnvelopeGroupState,    // groupState: neuer Zustand vom Admin
    MeshEnvelopeGroupLeave,    // group
    MeshEnvelopeGroupPicture,  // group + groupPicture (B7)
    MeshEnvelopeGroupPropose,  // group + subject (C) + subjectName (B9, gpr)
    MeshEnvelopeGroupVouch,    // group + subject (Admin) + subjectName (Gruppenname) (B9, gvo)
    MeshEnvelopeGroupKey,      // group + joinKey (@"" = geschlossen) (B10, gk)
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

// Gruppen: gid (16 Hex, klein) aus der Kopfzeile bzw. aus gj/gl; nil = keine Gruppe.
@property (nonatomic, readonly) NSString *group;
@property (nonatomic, readonly) NSString *groupState;  // gi/gs: dekodiertes Zustand-JSON (ungeprüft)
@property (nonatomic, readonly) NSString *joinName;    // gj: Anzeigename (ungeprüft, @"" = keiner)
@property (nonatomic, readonly) NSString *joinKey;     // gj: k (32 Hex, klein) oder nil; gk: k oder @"" (geschlossen)
@property (nonatomic, readonly) NSString *subject;     // gpr: vorgeschlagener pk; gvo: Admin-pk (64 Hex, klein)
@property (nonatomic, readonly) NSString *subjectName; // gpr: Name von C; gvo: Gruppenname (ungeprüft, @"" = keiner)
@property (nonatomic, readonly) NSData *groupPicture; // gp: rohe Bildbytes (ungeprüft, höchstens 64 KB, nie leer)
@property (nonatomic, readonly) BOOL anon;             // \1mesh:anon:1 (nur zusammen mit einer Textnachricht)

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

// Gruppen und Team-Chat
+ (NSString *)inGroup:(NSString *)gid plain:(NSString *)plain;   // Kopfzeile vor Nachricht/Reaktion/Löschen
+ (NSString *)groupInvite:(NSString *)stateJSON;
+ (NSString *)groupJoin:(NSString *)gid name:(NSString *)name;
+ (NSString *)groupJoin:(NSString *)gid name:(NSString *)name key:(NSString *)key;   // B10: per Link
+ (NSString *)groupPropose:(NSString *)gid candidate:(NSString *)pk name:(NSString *)name;
+ (NSString *)groupVouch:(NSString *)gid admin:(NSString *)admin groupName:(NSString *)name;
+ (NSString *)groupKey:(NSString *)gid key:(NSString *)key;   // nil/@"" = geschlossen
+ (NSString *)groupState:(NSString *)stateJSON;
+ (NSString *)groupLeave:(NSString *)gid;
+ (NSString *)groupPicture:(NSData *)bytes gid:(NSString *)gid;
+ (NSString *)anonMessage:(NSString *)text cmid:(NSString *)cmid;
+ (BOOL)isGroupId:(NSString *)gid;   // genau 16 Hex-Zeichen (Groß/klein egal)

+ (NSString *)newMessageId;   // 16 Hex-Zeichen (8 Zufallsbytes) wie Android
@end
