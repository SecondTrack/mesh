// Eine Zeile der Chatliste: Kontakt und letzte Nachricht.
//
// Schlüssel eines Chats (Spalte messages.chat): Pubkey des Kontakts, "g:<gid>" für eine Gruppe,
// "team" für den Team-Chat. Andere Schichten bilden und erkennen sie nur über diese Funktionen.
#import <Foundation/Foundation.h>

extern NSString *const MeshTeamChat;                 // "team"
NSString *MeshGroupChat(NSString *gid);              // "g:<gid>"
NSString *MeshGroupOfChat(NSString *chat);           // gid oder nil, wenn kein Gruppenchat
BOOL MeshIsTeamChat(NSString *chat);

typedef NS_ENUM(NSInteger, MeshGroupStatus) {        // Werte stehen in der Datenbank (groups.status)
    MeshGroupInvited   = 0,   // Einladung offen
    MeshGroupJoining   = 1,   // angenommen, gj unterwegs; das Gerät des Admins antwortet automatisch mit gs
    MeshGroupMember    = 2,
    MeshGroupLeft      = 3,   // selbst verlassen
    MeshGroupRemoved   = 4,   // vom Admin entfernt
    MeshGroupDissolved = 5,
    MeshGroupLinkJoining = 6,  // per Link beigetreten (B10), gs vom Gerät des Admins steht noch aus
    MeshGroupJoinFailed = 7,   // Link-Beitritt: nach 7 Tagen kein Zustand
    MeshGroupInviteExpired = 8 // Einladung abgelaufen: der Admin hat gewechselt (B9)
};

@interface MeshChat : NSObject
@property (nonatomic, copy)   NSString *pubkey;        // hex x-only pubkey des Kontakts
@property (nonatomic, copy)   NSString *name;          // Anzeigename (setzt MeshSession)
@property (nonatomic, assign) BOOL      unknown;       // Kontakt nicht angenommen
@property (nonatomic, copy)   NSString *ownName;       // vom Nutzer vergeben (aus dem Store)
@property (nonatomic, copy)   NSString *profileName;   // aus dem kind-0-Profil (aus dem Store)
@property (nonatomic, assign) NSInteger lastKind;      // MeshPayloadKind der letzten Nachricht
@property (nonatomic, copy)   NSString *lastContent;   // Anfang der letzten Nachricht (bei Medien nur der Marker)
@property (nonatomic, assign) long long ts;            // Unix-Sekunden der letzten Nachricht
@property (nonatomic, assign) BOOL      fromMe;        // letzte Nachricht war von mir
@property (nonatomic, assign) int       identitySlot;  // zu welcher eigenen Identität der Chat gehört
@property (nonatomic, copy)   NSString *identityPubkey;
@property (nonatomic, copy)   NSString *sender;        // Gruppe: Absender der letzten Nachricht (Pubkey)
@property (nonatomic, copy)   NSString *senderName;    // Gruppe: dessen Anzeigename (setzt MeshSession)
@property (nonatomic, assign) BOOL      isGroup, isTeam;
@property (nonatomic, assign) MeshGroupStatus groupStatus;
@property (nonatomic, copy)   NSString *inviter;       // Einladung: Anzeigename des Admins
@end

// Chatliste: neueste zuerst (ts), bei Gleichstand wie geliefert; der Team-Chat (isTeam) bleibt oben.
void MeshSortChatList(NSMutableArray *chats);
// Zeit einer Gruppenzeile: letzte Nachricht/Systemzeile oder Eintreffen der Einladung, das Spätere.
long long MeshGroupRowTime(long long lastMessage, long long arrived);
// Gruppenstand als Text: Zeile in der Chatliste bzw. Hinweis im Chat (warum nicht geschrieben werden
// kann). nil = normal (Vorschau bzw. kein Hinweis).
NSString *MeshGroupStatusPreview(MeshGroupStatus status);
NSString *MeshGroupStatusNote(MeshGroupStatus status);
