// Gruppen und Team-Chat (docs/TEAM_GROUPS_PROTOCOL.md): Zustand je Gruppe (versiegelt), offene
// Einladungen des Admins, der Einweg-Schlüssel des Team-Chats (versiegelt) und dessen eigene
// Warteschlange. Die Nachrichten selbst stehen wie alle in messages (Chat "g:<gid>" bzw. "team").
#import "MeshStore.h"
#import "MeshChat.h"

@interface MeshStore (Group)
// Gruppen. state: Zustand-JSON (MeshGroupState), wird versiegelt, ebenso inviter. nil = unbekannt.
- (BOOL)saveGroup:(NSString *)gid state:(NSString *)json status:(MeshGroupStatus)status inviter:(NSString *)inviter;
- (NSString *)groupState:(NSString *)gid status:(MeshGroupStatus *)status inviter:(NSString **)inviter;
- (BOOL)setGroupStatus:(MeshGroupStatus)status gid:(NSString *)gid;
- (NSArray *)groupIds;                                  // alle bekannten, älteste zuerst
- (NSArray *)groupIdsWithStatus:(MeshGroupStatus)status;
- (long long)groupCreated:(NSString *)gid;              // angelegt bzw. Einladung erhalten (Unix-Sekunden)
- (BOOL)deleteGroup:(NSString *)gid;                    // mit Nachrichten (+ Tombstones) und Einladungen
- (int)invitationCountFrom:(NSString *)inviter;         // offene Einladungen an mich (nil = alle)
// Gruppenbild (B7): Base64 der rohen Bytes, versiegelt an die gid. nil/@"" = entfernen. Nur bekannte Gruppen.
- (BOOL)setGroupPicture:(NSString *)base64 gid:(NSString *)gid;
- (NSString *)groupPicture:(NSString *)gid;             // nil = keins

// Einladungen, die der Admin verschickt hat (Pubkey versiegelt, Zeitpunkt).
- (void)addInvite:(NSString *)pubkey group:(NSString *)gid at:(long long)time;
- (BOOL)hasInvite:(NSString *)pubkey group:(NSString *)gid since:(long long)time;
- (void)removeInvite:(NSString *)pubkey group:(NSString *)gid;
- (NSArray *)invitesForGroup:(NSString *)gid since:(long long)time;
- (void)pruneInvitesBefore:(long long)time;

// Einladungen von (noch) nicht angenommenen Absendern (B8.5): versiegeltes JSON, nicht als erledigt gemerkt.
- (BOOL)holdInvite:(NSString *)json at:(long long)time;
- (NSArray *)heldInvites;                               // @[@(id), JSON], die ältesten zuerst (JSON @"" = nicht lesbar)
- (void)removeHeldInvite:(long long)rowId;
- (int)heldInviteCount;
- (void)pruneHeldInvitesBefore:(long long)time;

// B10: Link-Geheimnis k (32 Hex, versiegelt; nil = keins) und Beginn eines Link-Beitritts (0 = keiner).
- (BOOL)setGroupLinkKey:(NSString *)hex gid:(NSString *)gid;
- (NSString *)groupLinkKey:(NSString *)gid;
- (BOOL)setGroupLinkAt:(long long)time gid:(NSString *)gid;
- (long long)groupLinkAt:(NSString *)gid;
- (void)removeInvitesForGroup:(NSString *)gid;          // B9: alter Admin vergisst seine offenen Einladungen
- (BOOL)isQueuedEvent:(NSString *)eventId;              // noch in der Warteschlange (kein Relay hat es bestätigt)

// Kleine versiegelte Datensätze zu Gruppen (B9/B10). data ist an Art und gid gebunden; gid nil = ohne Gruppe.
typedef NS_ENUM(int, MeshGroupRecord) {
    MeshGroupRecordLinkJoin = 1,   // Admin: Link-Beitritt (Zeit zählt, 10 je Stunde)
    MeshGroupRecordRemoved  = 2,   // Admin: entfernter pk (24 h kein Link-Beitritt)
    MeshGroupRecordProposal = 3,   // Admin: Vorschlag (JSON)
    MeshGroupRecordVoucher  = 4,   // Bürgschaft (JSON, gid nil)
    MeshGroupRecordDeferred = 5    // aufgeschobene Sendung (JSON, gid nil)
};
- (BOOL)addGroupRecord:(MeshGroupRecord)kind gid:(NSString *)gid data:(NSString *)data at:(long long)time;
- (NSArray *)groupRecords:(MeshGroupRecord)kind gid:(NSString *)gid;   // @[@(id), @(at), data], älteste zuerst (data @"" = nicht lesbar)
- (int)groupRecordCount:(MeshGroupRecord)kind gid:(NSString *)gid since:(long long)time;
- (void)removeGroupRecord:(long long)rowId;
- (void)removeGroupRecords:(MeshGroupRecord)kind gid:(NSString *)gid;
- (void)pruneGroupRecords:(MeshGroupRecord)kind before:(long long)time;

// Gruppennachrichten: Doppelte (gleicher Absender + cmid) und "für alle löschen" nur eigener.
- (BOOL)hasMessage:(NSString *)cmid chat:(NSString *)chat sender:(NSString *)sender;
- (BOOL)deleteMessageWithKey:(NSString *)key chat:(NSString *)chat sender:(NSString *)sender;
- (BOOL)setReaction:(NSString *)emoji key:(NSString *)key chat:(NSString *)chat sender:(NSString *)sender;   // nur auf Vorhandenes

// Team-Chat
- (NSString *)teamKey;                                  // Seckey von E als Hex, nil = keiner
- (BOOL)setTeamKey:(NSString *)hex;
- (long long)teamValue:(const char *)column;            // since, started, hidden, muted
- (BOOL)setTeamValue:(const char *)column value:(long long)value;
- (BOOL)queueTeamEvent:(NSString *)json eventId:(NSString *)eventId created:(long long)created;
- (NSArray *)queuedTeamEvents;                          // JSON, die ältesten zuerst
- (void)removeTeamEvent:(NSString *)eventId;
- (BOOL)expireTeamQueuedBefore:(long long)time;
- (BOOL)deleteTeamPersonal;                             // "Neu anfangen": persönliche Nachrichten und Warteschlange
- (void)moveTeamGreetingBefore:(long long)ts;           // Begrüßung bleibt die erste Blase
@end
