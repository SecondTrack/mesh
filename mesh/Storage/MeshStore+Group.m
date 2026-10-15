#import "MeshStore+Group.h"
#import "MeshStore+Internal.h"
#import "MeshMessage.h"
#import "MeshTime.h"

static NSString *groupContext(NSString *gid) { return [@"groups.state|" stringByAppendingString:gid ?: @""]; }
static NSString *groupPicContext(NSString *gid) { return [@"groups.pic|" stringByAppendingString:gid ?: @""]; }
static NSString *teamOutboxContext(NSString *eventId) { return [@"team_outbox.event|" stringByAppendingString:eventId ?: @""]; }
static NSString *const kTeamKeyContext = @"team.ekey";
static NSString *const kHeldContext = @"held_invites.data";
static NSString *groupKeyContext(NSString *gid) { return [@"groups.lkey|" stringByAppendingString:gid ?: @""]; }
static NSString *recordContext(MeshGroupRecord kind, NSString *gid) { return [NSString stringWithFormat:@"group_records.data|%d|%@", (int)kind, gid ?: @""]; }

@implementation MeshStore (Group)

#pragma mark - Gruppen

- (BOOL)saveGroup:(NSString *)gid state:(NSString *)json status:(MeshGroupStatus)status inviter:(NSString *)inviter {
    NSString *sealed = gid.length ? [self seal:json context:groupContext(gid)] : nil;
    if (!sealed) return NO;
    NSString *sealedInviter = inviter.length ? [self seal:inviter context:inviterContext(gid)] : nil;   // wer eingeladen hat: versiegelt
    if (inviter.length && !sealedInviter) return NO;
    // Kein UPSERT: das sqlite von iOS 5/6 kennt es nicht. "created" bleibt beim Ändern.
    BOOL known = [self exists:"SELECT 1 FROM groups WHERE gid=?" text:gid];
    sqlite3_stmt *st = [self prepare:known ? "UPDATE groups SET status=?2, state=?3, inviter=?4 WHERE gid=?1"
                                           : "INSERT INTO groups(gid, status, state, inviter, created) VALUES(?1,?2,?3,?4,?5)"];
    if (!st) return NO;
    bindText(st, 1, gid);
    sqlite3_bind_int(st, 2, (int)status);
    bindText(st, 3, sealed);
    bindText(st, 4, sealedInviter);
    if (!known) sqlite3_bind_int64(st, 5, MeshNow());
    BOOL ok = sqlite3_step(st) == SQLITE_DONE;
    sqlite3_finalize(st);
    return ok;
}

- (NSString *)groupState:(NSString *)gid status:(MeshGroupStatus *)status inviter:(NSString **)inviter {
    sqlite3_stmt *st = [self prepare:"SELECT status, state, inviter FROM groups WHERE gid=?"];
    if (!st) return nil;
    bindText(st, 1, gid);
    NSString *json = nil;
    if (sqlite3_step(st) == SQLITE_ROW) {
        json = [self open:columnText(st, 1) context:groupContext(gid)];
        if (status) *status = (MeshGroupStatus)sqlite3_column_int(st, 0);
        if (inviter) *inviter = [self openPubkey:columnText(st, 2) context:inviterContext(gid)];
    }
    sqlite3_finalize(st);
    return json;
}

- (BOOL)setGroupStatus:(MeshGroupStatus)status gid:(NSString *)gid {
    sqlite3_stmt *st = [self prepare:"UPDATE groups SET status=? WHERE gid=?"];
    if (!st) return NO;
    sqlite3_bind_int(st, 1, (int)status);
    bindText(st, 2, gid);
    BOOL ok = sqlite3_step(st) == SQLITE_DONE && sqlite3_changes(self.db) > 0;
    sqlite3_finalize(st);
    return ok;
}

- (NSArray *)groupIds {
    NSMutableArray *out = [NSMutableArray array];
    sqlite3_stmt *st = [self prepare:"SELECT gid FROM groups ORDER BY created, rowid"];
    while (st && sqlite3_step(st) == SQLITE_ROW) { NSString *g = columnText(st, 0); if (g) [out addObject:g]; }
    sqlite3_finalize(st);
    return out;
}

- (NSArray *)groupIdsWithStatus:(MeshGroupStatus)status {
    NSMutableArray *out = [NSMutableArray array];
    sqlite3_stmt *st = [self prepare:"SELECT gid FROM groups WHERE status=? ORDER BY created, rowid"];
    if (st) sqlite3_bind_int(st, 1, (int)status);
    while (st && sqlite3_step(st) == SQLITE_ROW) { NSString *g = columnText(st, 0); if (g) [out addObject:g]; }
    sqlite3_finalize(st);
    return out;
}

- (long long)groupCreated:(NSString *)gid {
    sqlite3_stmt *st = [self prepare:"SELECT created FROM groups WHERE gid=?"];
    if (!st) return 0;
    bindText(st, 1, gid);
    long long t = sqlite3_step(st) == SQLITE_ROW ? sqlite3_column_int64(st, 0) : 0;
    sqlite3_finalize(st);
    return t;
}

- (BOOL)setGroupArrived:(long long)time gid:(NSString *)gid {
    sqlite3_stmt *st = [self prepare:"UPDATE groups SET created=? WHERE gid=?"];
    if (!st) return NO;
    sqlite3_bind_int64(st, 1, time);
    bindText(st, 2, gid);
    BOOL ok = sqlite3_step(st) == SQLITE_DONE && sqlite3_changes(self.db) > 0;
    sqlite3_finalize(st);
    return ok;
}

- (BOOL)deleteGroup:(NSString *)gid {
    NSString *chat = MeshGroupChat(gid);
    BOOL ok = sqlite3_exec(self.db, "BEGIN", NULL, NULL, NULL) == SQLITE_OK
        && [self run:"INSERT OR IGNORE INTO deleted(event_id) SELECT event_id FROM messages WHERE chat=? AND event_id IS NOT NULL" text:chat]
        && [self run:"DELETE FROM outbox WHERE event_id IN (SELECT event_id FROM messages WHERE chat=?)" text:chat]
        && [self run:"DELETE FROM messages WHERE chat=?" text:chat]
        && [self run:"DELETE FROM chats WHERE chat=?" text:chat]
        && [self run:"DELETE FROM group_invites WHERE gid=?" text:gid]
        && [self run:"DELETE FROM group_records WHERE gid=?" text:gid]
        && [self run:"DELETE FROM groups WHERE gid=?" text:gid];
    if (ok && sqlite3_exec(self.db, "COMMIT", NULL, NULL, NULL) == SQLITE_OK) return YES;
    sqlite3_exec(self.db, "ROLLBACK", NULL, NULL, NULL);
    return NO;
}

// Einladende sind versiegelt: offene Einladungen (höchstens ~50) einzeln öffnen und vergleichen.
- (int)invitationCountFrom:(NSString *)inviter {
    sqlite3_stmt *st = [self prepare:"SELECT gid, inviter FROM groups WHERE status=0"];
    if (!st) return INT_MAX;   // im Zweifel nichts mehr annehmen
    int n = 0;
    while (sqlite3_step(st) == SQLITE_ROW)
        if (!inviter || [[self openPubkey:columnText(st, 1) context:inviterContext(columnText(st, 0))] isEqualToString:inviter]) n++;
    sqlite3_finalize(st);
    return n;
}

- (BOOL)setGroupPicture:(NSString *)base64 gid:(NSString *)gid {
    if (!gid.length) return NO;
    NSString *sealed = base64.length ? [self seal:base64 context:groupPicContext(gid)] : nil;
    if (base64.length && !sealed) return NO;
    sqlite3_stmt *st = [self prepare:"UPDATE groups SET pic=? WHERE gid=?"];
    if (!st) return NO;
    bindText(st, 1, sealed);
    bindText(st, 2, gid);
    BOOL ok = sqlite3_step(st) == SQLITE_DONE && sqlite3_changes(self.db) > 0;
    sqlite3_finalize(st);
    return ok;
}

- (NSString *)groupPicture:(NSString *)gid {
    sqlite3_stmt *st = [self prepare:"SELECT pic FROM groups WHERE gid=?"];
    if (!st) return nil;
    bindText(st, 1, gid);
    NSString *sealed = sqlite3_step(st) == SQLITE_ROW ? columnText(st, 0) : nil;
    sqlite3_finalize(st);
    NSString *b64 = sealed.length ? [self open:sealed context:groupPicContext(gid)] : nil;
    return b64.length ? b64 : nil;
}

#pragma mark - Link (B10)

- (BOOL)setGroupLinkKey:(NSString *)hex gid:(NSString *)gid {
    if (!gid.length) return NO;
    NSString *sealed = hex.length ? [self seal:hex context:groupKeyContext(gid)] : nil;
    if (hex.length && !sealed) return NO;
    sqlite3_stmt *st = [self prepare:"UPDATE groups SET lkey=? WHERE gid=?"];
    if (!st) return NO;
    bindText(st, 1, sealed);
    bindText(st, 2, gid);
    BOOL ok = sqlite3_step(st) == SQLITE_DONE && sqlite3_changes(self.db) > 0;
    sqlite3_finalize(st);
    return ok;
}

- (NSString *)groupLinkKey:(NSString *)gid {
    sqlite3_stmt *st = [self prepare:"SELECT lkey FROM groups WHERE gid=?"];
    if (!st) return nil;
    bindText(st, 1, gid);
    NSString *sealed = sqlite3_step(st) == SQLITE_ROW ? columnText(st, 0) : nil;
    sqlite3_finalize(st);
    NSString *k = sealed.length ? [self open:sealed context:groupKeyContext(gid)] : nil;
    return k.length == 32 ? k : nil;
}

- (BOOL)setGroupLinkAt:(long long)t gid:(NSString *)gid {
    sqlite3_stmt *st = [self prepare:"UPDATE groups SET link_at=? WHERE gid=?"];
    if (!st) return NO;
    sqlite3_bind_int64(st, 1, t);
    bindText(st, 2, gid);
    BOOL ok = sqlite3_step(st) == SQLITE_DONE && sqlite3_changes(self.db) > 0;
    sqlite3_finalize(st);
    return ok;
}

- (long long)groupLinkAt:(NSString *)gid {
    sqlite3_stmt *st = [self prepare:"SELECT link_at FROM groups WHERE gid=?"];
    if (!st) return 0;
    bindText(st, 1, gid);
    long long t = sqlite3_step(st) == SQLITE_ROW ? sqlite3_column_int64(st, 0) : 0;
    sqlite3_finalize(st);
    return t;
}

- (void)removeInvitesForGroup:(NSString *)gid { [self run:"DELETE FROM group_invites WHERE gid=?" text:gid]; }

- (BOOL)isQueuedEvent:(NSString *)eventId { return eventId.length && [self exists:"SELECT 1 FROM outbox WHERE event_id=?" text:eventId]; }

#pragma mark - Datensätze (B9/B10)

- (BOOL)addGroupRecord:(MeshGroupRecord)kind gid:(NSString *)gid data:(NSString *)data at:(long long)t {
    NSString *sealed = [self seal:data ?: @"" context:recordContext(kind, gid)];
    if (!sealed) return NO;
    sqlite3_stmt *st = [self prepare:"INSERT INTO group_records(kind, gid, at, data) VALUES(?,?,?,?)"];
    if (!st) return NO;
    sqlite3_bind_int(st, 1, (int)kind); bindText(st, 2, gid); sqlite3_bind_int64(st, 3, t); bindText(st, 4, sealed);
    BOOL ok = sqlite3_step(st) == SQLITE_DONE;
    sqlite3_finalize(st);
    return ok;
}

- (NSArray *)groupRecords:(MeshGroupRecord)kind gid:(NSString *)gid {
    NSMutableArray *out = [NSMutableArray array];
    sqlite3_stmt *st = [self prepare:gid ? "SELECT id, at, data FROM group_records WHERE kind=? AND gid=? ORDER BY at, id"
                           : "SELECT id, at, data FROM group_records WHERE kind=? AND gid IS NULL ORDER BY at, id"];
    if (!st) return out;
    sqlite3_bind_int(st, 1, (int)kind);
    if (gid) bindText(st, 2, gid);
    while (sqlite3_step(st) == SQLITE_ROW) {
        NSString *data = [self open:columnText(st, 2) context:recordContext(kind, gid)];
        [out addObject:@[@(sqlite3_column_int64(st, 0)), @(sqlite3_column_int64(st, 1)), data ?: @""]];
    }
    sqlite3_finalize(st);
    return out;
}

- (int)groupRecordCount:(MeshGroupRecord)kind gid:(NSString *)gid since:(long long)t {
    sqlite3_stmt *st = [self prepare:gid ? "SELECT COUNT(*) FROM group_records WHERE kind=? AND at>=? AND gid=?"
                                         : "SELECT COUNT(*) FROM group_records WHERE kind=? AND at>=? AND gid IS NULL"];
    if (!st) return INT_MAX;   // im Zweifel: Grenze erreicht
    sqlite3_bind_int(st, 1, (int)kind); sqlite3_bind_int64(st, 2, t);
    if (gid) bindText(st, 3, gid);
    int n = sqlite3_step(st) == SQLITE_ROW ? sqlite3_column_int(st, 0) : INT_MAX;
    sqlite3_finalize(st);
    return n;
}

- (void)removeGroupRecord:(long long)rowId {
    sqlite3_stmt *st = [self prepare:"DELETE FROM group_records WHERE id=?"];
    if (!st) return;
    sqlite3_bind_int64(st, 1, rowId);
    sqlite3_step(st);
    sqlite3_finalize(st);
}

- (void)removeGroupRecords:(MeshGroupRecord)kind gid:(NSString *)gid {
    sqlite3_stmt *st = [self prepare:gid ? "DELETE FROM group_records WHERE kind=? AND gid=?" : "DELETE FROM group_records WHERE kind=? AND gid IS NULL"];
    if (!st) return;
    sqlite3_bind_int(st, 1, (int)kind);
    if (gid) bindText(st, 2, gid);
    sqlite3_step(st);
    sqlite3_finalize(st);
}

- (void)pruneGroupRecords:(MeshGroupRecord)kind before:(long long)t {
    sqlite3_stmt *st = [self prepare:"DELETE FROM group_records WHERE kind=? AND at<?"];
    if (!st) return;
    sqlite3_bind_int(st, 1, (int)kind); sqlite3_bind_int64(st, 2, t);
    sqlite3_step(st);
    sqlite3_finalize(st);
}

#pragma mark - Einladungen

// Eingeladene stehen versiegelt (an die gid gebunden): je Gruppe höchstens ~20 Zeilen, einzeln geöffnet.
// Zeilen: rowid -> Pubkey, nur ab Zeitpunkt t.
- (NSDictionary *)inviteRows:(NSString *)gid since:(long long)t order:(NSMutableArray *)order {
    NSMutableDictionary *rows = [NSMutableDictionary dictionary];
    sqlite3_stmt *st = [self prepare:"SELECT rowid, pubkey FROM group_invites WHERE gid=? AND at>=? ORDER BY at, rowid"];
    if (!st) return rows;
    bindText(st, 1, gid); sqlite3_bind_int64(st, 2, t);
    while (sqlite3_step(st) == SQLITE_ROW) {
        NSString *pk = [self openPubkey:columnText(st, 1) context:inviteeContext(gid)];
        if (!pk) continue;
        rows[@(sqlite3_column_int64(st, 0))] = pk;
        [order addObject:@(sqlite3_column_int64(st, 0))];
    }
    sqlite3_finalize(st);
    return rows;
}

- (void)removeInvite:(NSString *)pubkey group:(NSString *)gid {
    NSDictionary *rows = [self inviteRows:gid since:LLONG_MIN order:nil];
    for (NSNumber *row in rows) {
        if (![rows[row] isEqualToString:pubkey]) continue;
        sqlite3_stmt *st = [self prepare:"DELETE FROM group_invites WHERE rowid=?"];
        if (!st) continue;
        sqlite3_bind_int64(st, 1, row.longLongValue);
        sqlite3_step(st);
        sqlite3_finalize(st);
    }
}

- (void)addInvite:(NSString *)pubkey group:(NSString *)gid at:(long long)t {
    NSString *sealed = pubkey.length ? [self seal:pubkey context:inviteeContext(gid)] : nil;
    if (!sealed) return;
    [self removeInvite:pubkey group:gid];   // ersetzt eine ältere (Zeit neu)
    sqlite3_stmt *st = [self prepare:"INSERT INTO group_invites(gid, pubkey, at) VALUES(?,?,?)"];
    if (!st) return;
    bindText(st, 1, gid); bindText(st, 2, sealed); sqlite3_bind_int64(st, 3, t);
    sqlite3_step(st);
    sqlite3_finalize(st);
}

- (BOOL)hasInvite:(NSString *)pubkey group:(NSString *)gid since:(long long)t {
    return pubkey && [[[self inviteRows:gid since:t order:nil] allValues] containsObject:pubkey];
}

- (NSArray *)invitesForGroup:(NSString *)gid since:(long long)t {
    NSMutableArray *order = [NSMutableArray array], *out = [NSMutableArray array];
    NSDictionary *rows = [self inviteRows:gid since:t order:order];
    for (NSNumber *row in order) if (![out containsObject:rows[row]]) [out addObject:rows[row]];
    return out;
}

- (void)pruneInvitesBefore:(long long)t {
    sqlite3_stmt *st = [self prepare:"DELETE FROM group_invites WHERE at<?"];
    if (!st) return;
    sqlite3_bind_int64(st, 1, t);
    sqlite3_step(st);
    sqlite3_finalize(st);
}

#pragma mark - Zurückgehaltene Einladungen (B8.5)

- (BOOL)holdInvite:(NSString *)json at:(long long)t {
    NSString *sealed = json.length ? [self seal:json context:kHeldContext] : nil;
    if (!sealed) return NO;
    sqlite3_stmt *st = [self prepare:"INSERT INTO held_invites(at, data) VALUES(?,?)"];
    if (!st) return NO;
    sqlite3_bind_int64(st, 1, t); bindText(st, 2, sealed);
    BOOL ok = sqlite3_step(st) == SQLITE_DONE;
    sqlite3_finalize(st);
    return ok;
}

- (NSArray *)heldInvites {
    NSMutableArray *out = [NSMutableArray array];
    sqlite3_stmt *st = [self prepare:"SELECT id, data FROM held_invites ORDER BY at, id"];
    while (st && sqlite3_step(st) == SQLITE_ROW) {
        NSString *json = [self open:columnText(st, 1) context:kHeldContext];
        [out addObject:@[@(sqlite3_column_int64(st, 0)), json ?: @""]];   // nicht lesbar: leer (wird verworfen)
    }
    sqlite3_finalize(st);
    return out;
}

- (void)removeHeldInvite:(long long)rowId {
    sqlite3_stmt *st = [self prepare:"DELETE FROM held_invites WHERE id=?"];
    if (!st) return;
    sqlite3_bind_int64(st, 1, rowId);
    sqlite3_step(st);
    sqlite3_finalize(st);
}

- (int)heldInviteCount {
    sqlite3_stmt *st = [self prepare:"SELECT COUNT(*) FROM held_invites"];
    int n = (st && sqlite3_step(st) == SQLITE_ROW) ? sqlite3_column_int(st, 0) : INT_MAX;
    sqlite3_finalize(st);
    return n;
}

- (void)pruneHeldInvitesBefore:(long long)t {
    sqlite3_stmt *st = [self prepare:"DELETE FROM held_invites WHERE at<?"];
    if (!st) return;
    sqlite3_bind_int64(st, 1, t);
    sqlite3_step(st);
    sqlite3_finalize(st);
}

#pragma mark - Gruppennachrichten

// Absender sind versiegelt: über den Index (chat, cmid) die wenigen Kandidaten holen, dann vergleichen.
- (BOOL)hasMessage:(NSString *)cmid chat:(NSString *)chat sender:(NSString *)sender {
    if (!cmid.length || !sender.length) return NO;
    sqlite3_stmt *st = [self prepare:"SELECT sender, event_id FROM messages WHERE chat=? AND cmid=?"];
    if (!st) return NO;
    bindText(st, 1, chat); bindText(st, 2, cmid);
    BOOL found = NO;
    while (!found && sqlite3_step(st) == SQLITE_ROW)
        found = [[self senderFrom:columnText(st, 0) chat:chat eventId:columnText(st, 1)] isEqualToString:sender];
    sqlite3_finalize(st);
    return found;
}

// Nur Nachrichten dieses Absenders (ein Mitglied darf keine fremden löschen), mit Tombstone.
- (BOOL)deleteMessageWithKey:(NSString *)key chat:(NSString *)chat sender:(NSString *)sender {
    if (!key.length || !sender.length) return NO;
    sqlite3_stmt *st = [self prepare:"SELECT rowid, sender, event_id FROM messages WHERE chat=?1 AND from_me=0 AND (cmid=?2 OR event_id=?2)"];
    if (!st) return NO;
    bindText(st, 1, chat); bindText(st, 2, key);
    NSMutableArray *rows = [NSMutableArray array];
    while (sqlite3_step(st) == SQLITE_ROW)
        if ([[self senderFrom:columnText(st, 1) chat:chat eventId:columnText(st, 2)] isEqualToString:sender]) [rows addObject:@(sqlite3_column_int64(st, 0))];
    sqlite3_finalize(st);
    for (NSNumber *row in rows) [self deleteMessage:row.longLongValue];
    return rows.count > 0;
}

// Reaktion eines Mitglieds: in der Spalte des Gegenübers (eine je Nachricht, die letzte gilt).
- (BOOL)setReaction:(NSString *)emoji key:(NSString *)key chat:(NSString *)chat sender:(NSString *)sender {
    if (!key.length || !sender.length) return NO;
    sqlite3_stmt *st = [self prepare:"SELECT rowid FROM messages WHERE chat=?1 AND (cmid=?2 OR event_id=?2)"];
    if (!st) return NO;
    bindText(st, 1, chat); bindText(st, 2, key);
    NSMutableArray *rows = [NSMutableArray array];
    while (sqlite3_step(st) == SQLITE_ROW) [rows addObject:@(sqlite3_column_int64(st, 0))];
    sqlite3_finalize(st);
    for (NSNumber *row in rows) {
        NSString *sealed = emoji.length ? [self seal:emoji context:reactionContext(chat, row.longLongValue, NO)] : nil;
        if (emoji.length && !sealed) return NO;
        if (!(st = [self prepare:"UPDATE messages SET react_peer=? WHERE rowid=?"])) return NO;
        bindText(st, 1, sealed);
        sqlite3_bind_int64(st, 2, row.longLongValue);
        sqlite3_step(st);
        sqlite3_finalize(st);
    }
    return rows.count > 0;
}

#pragma mark - Team-Chat

- (void)ensureTeamRow { sqlite3_exec(self.db, "INSERT OR IGNORE INTO team(id) VALUES(1)", NULL, NULL, NULL); }

- (NSString *)teamKey {
    sqlite3_stmt *st = [self prepare:"SELECT ekey FROM team WHERE id=1"];
    NSString *hex = (st && sqlite3_step(st) == SQLITE_ROW) ? [self open:columnText(st, 0) context:kTeamKeyContext] : nil;
    sqlite3_finalize(st);
    return hex.length == 64 ? hex : nil;
}

- (BOOL)setTeamKey:(NSString *)hex {
    NSString *sealed = hex.length == 64 ? [self seal:hex context:kTeamKeyContext] : nil;
    if (!sealed) return NO;
    [self ensureTeamRow];
    return [self run:"UPDATE team SET ekey=? WHERE id=1" text:sealed];
}

static BOOL teamColumn(const char *c) {
    static const char *allowed[] = { "since", "started", "hidden", "muted" };   // "used" nicht mehr (Metadatum ohne Leser)
    for (size_t i = 0; i < sizeof(allowed) / sizeof(allowed[0]); i++) if (!strcmp(c, allowed[i])) return YES;
    return NO;
}

- (long long)teamValue:(const char *)column {
    if (!teamColumn(column)) return 0;
    NSString *sql = [NSString stringWithFormat:@"SELECT %s FROM team WHERE id=1", column];
    sqlite3_stmt *st = [self prepare:sql.UTF8String];
    long long v = (st && sqlite3_step(st) == SQLITE_ROW) ? sqlite3_column_int64(st, 0) : 0;
    sqlite3_finalize(st);
    return v;
}

- (BOOL)setTeamValue:(const char *)column value:(long long)value {
    if (!teamColumn(column)) return NO;
    [self ensureTeamRow];
    NSString *sql = [NSString stringWithFormat:@"UPDATE team SET %s=? WHERE id=1", column];
    sqlite3_stmt *st = [self prepare:sql.UTF8String];
    if (!st) return NO;
    sqlite3_bind_int64(st, 1, value);
    BOOL ok = sqlite3_step(st) == SQLITE_DONE;
    sqlite3_finalize(st);
    return ok;
}

- (BOOL)queueTeamEvent:(NSString *)json eventId:(NSString *)eventId created:(long long)created {
    NSString *sealed = eventId.length ? [self seal:json context:teamOutboxContext(eventId)] : nil;
    if (!sealed) return NO;
    sqlite3_stmt *st = [self prepare:"INSERT OR REPLACE INTO team_outbox(event_id, event, created) VALUES(?,?,?)"];
    if (!st) return NO;
    bindText(st, 1, eventId); bindText(st, 2, sealed); sqlite3_bind_int64(st, 3, created);
    BOOL ok = sqlite3_step(st) == SQLITE_DONE;
    sqlite3_finalize(st);
    return ok;
}

- (NSArray *)queuedTeamEvents {
    NSMutableArray *out = [NSMutableArray array];
    sqlite3_stmt *st = [self prepare:"SELECT event_id, event FROM team_outbox ORDER BY created LIMIT 20"];
    while (st && sqlite3_step(st) == SQLITE_ROW) {
        NSString *json = [self open:columnText(st, 1) context:teamOutboxContext(columnText(st, 0))];
        if (json) [out addObject:json];
    }
    sqlite3_finalize(st);
    return out;
}

- (void)removeTeamEvent:(NSString *)eventId { [self run:"DELETE FROM team_outbox WHERE event_id=?" text:eventId]; }

- (BOOL)expireTeamQueuedBefore:(long long)t {
    sqlite3_stmt *st = [self prepare:"UPDATE messages SET status=?1 WHERE status=?2 AND chat='team' "
                                     "AND event_id IN (SELECT event_id FROM team_outbox WHERE created < ?3)"];
    if (!st) return NO;
    sqlite3_bind_int(st, 1, MeshMessageFailed);
    sqlite3_bind_int(st, 2, MeshMessageSending);
    sqlite3_bind_int64(st, 3, t);
    BOOL changed = sqlite3_step(st) == SQLITE_DONE && sqlite3_changes(self.db) > 0;
    sqlite3_finalize(st);
    if ((st = [self prepare:"DELETE FROM team_outbox WHERE created < ?"])) {
        sqlite3_bind_int64(st, 1, t);
        sqlite3_step(st);
        sqlite3_finalize(st);
    }
    return changed;
}

// Rundbriefe (sender 'all') und die Begrüßung ('app') bleiben; alles Persönliche geht, mit Tombstones,
// damit Relays die Antworten an den alten E nicht wieder einspielen.
- (BOOL)deleteTeamPersonal {
    BOOL ok = sqlite3_exec(self.db, "BEGIN", NULL, NULL, NULL) == SQLITE_OK
        && sqlite3_exec(self.db, "INSERT OR IGNORE INTO deleted(event_id) SELECT event_id FROM messages "
                                 "WHERE chat='team' AND sender IS NULL AND event_id IS NOT NULL;"
                                 "DELETE FROM messages WHERE chat='team' AND sender IS NULL;"
                                 "DELETE FROM team_outbox;", NULL, NULL, NULL) == SQLITE_OK;
    if (ok && sqlite3_exec(self.db, "COMMIT", NULL, NULL, NULL) == SQLITE_OK) return YES;
    sqlite3_exec(self.db, "ROLLBACK", NULL, NULL, NULL);
    return NO;
}

- (void)moveTeamGreetingBefore:(long long)ts {
    sqlite3_stmt *st = [self prepare:"UPDATE messages SET ts=?1 WHERE chat='team' AND sender='app' AND ts>?1"];
    if (!st) return;
    sqlite3_bind_int64(st, 1, ts);
    sqlite3_step(st);
    sqlite3_finalize(st);
}

@end
