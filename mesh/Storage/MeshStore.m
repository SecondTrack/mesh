#import "MeshStore.h"
#import "MeshStore+Internal.h"
#import "MeshChat.h"
#import "MeshMessage.h"
#import "MeshPayload.h"
#import "MeshSeal.h"
#import "MeshMemory.h"
#import "MeshText.h"
#import "MeshProfile.h"
#import "MeshTime.h"

@implementation MeshStore {
    sqlite3 *_db;
    NSString *_path;
    NSData *_key;      // Datenschlüssel, nur im entsperrten Zustand gesetzt
}

#pragma mark - sqlite-Hilfen

- (sqlite3 *)db { return _db; }

- (sqlite3_stmt *)prepare:(const char *)sql {
    sqlite3_stmt *st = NULL;
    return sqlite3_prepare_v2(_db, sql, -1, &st, NULL) == SQLITE_OK ? st : NULL;
}

// Führt eine Anweisung mit einem Text-Parameter aus, die keine Zeilen liefert.
- (BOOL)run:(const char *)sql text:(NSString *)arg {
    sqlite3_stmt *st = [self prepare:sql];
    if (!st) return NO;
    bindText(st, 1, arg);
    BOOL ok = sqlite3_step(st) == SQLITE_DONE;
    sqlite3_finalize(st);
    return ok;
}

// YES, wenn die Abfrage mit einem Text-Parameter mindestens eine Zeile liefert.
- (BOOL)exists:(const char *)sql text:(NSString *)arg {
    sqlite3_stmt *st = [self prepare:sql];
    if (!st) return NO;
    bindText(st, 1, arg);
    BOOL found = sqlite3_step(st) == SQLITE_ROW;
    sqlite3_finalize(st);
    return found;
}

#pragma mark - Verschlüsselte Felder

- (void)setDataKey:(NSData *)key { [self setDataKey:key knownSealed:NO]; }

- (void)setDataKey:(NSData *)key knownSealed:(BOOL)knownSealed {
    if (_key) MeshWipe(_key);
    _key = key.length == 32 ? [key mutableCopy] : nil;
    if (knownSealed) _migrated = YES;   // gilt auch, wenn jemand user_version in der Datei zurücksetzt
    if (_key) [self migrateSeals];   // räumt danach per VACUUM auf; sonst ist nichts zu tun (secure_delete)
}

- (BOOL)sealed { return _migrated; }

// nil, wenn kein Schlüssel gesetzt ist, dann wird nicht geschrieben (nie Klartext).
- (NSString *)seal:(NSString *)plain context:(NSString *)context {
    return [MeshSeal seal:plain ?: @"" key:_key context:context];
}

// Nach der Migration gilt nur enc2 mit passendem Kontext; Klartext in der Datei wird nicht
// angezeigt (sonst ließen sich mit Schreibzugriff Nachrichten unterschieben).
- (NSString *)open:(NSString *)stored context:(NSString *)context {
    if (!stored || !_key) return nil;
    if ([MeshSeal isSealed:stored]) return [MeshSeal open:stored key:_key context:context];
    return _migrated ? nil : [self legacyPlain:stored];
}

// Wert aus einer älteren Version: enc1 (ohne Kontext) oder Klartext.
- (NSString *)legacyPlain:(NSString *)value {
    if ([MeshSeal isLegacySealed:value]) {
        NSString *plain = [MeshSeal openLegacy:value key:_key];
        if (plain) return plain;   // sonst war es Klartext, der zufällig mit "enc1:" beginnt
    }
    return value ?: @"";
}

#pragma mark - Öffnen

// Mit Gerätecode ist die Datei bei gesperrtem Gerät unlesbar (auch Journal und Pubkeys im Klartext).
// Ob das Flag greift, zeigt erst ein Schreibzugriff; wo nicht, ohne. macOS (Tests) kennt es nicht.
- (BOOL)openFile:(NSString *)path {
    int flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE;
#if TARGET_OS_IPHONE
    if (sqlite3_open_v2(path.UTF8String, &_db, flags | SQLITE_OPEN_FILEPROTECTION_COMPLETE, NULL) == SQLITE_OK
        && sqlite3_exec(_db, "BEGIN IMMEDIATE; ROLLBACK", NULL, NULL, NULL) == SQLITE_OK) return YES;
    sqlite3_close(_db);
    _db = NULL;
#endif
    if (sqlite3_open_v2(path.UTF8String, &_db, flags, NULL) == SQLITE_OK) return YES;
    sqlite3_close(_db);
    _db = NULL;
    return NO;
}

// Das sqlite-Flag wirkt nur beim Anlegen; Dateien älterer Versionen bekommen den Schutz hier.
- (void)protectFiles {
#if TARGET_OS_IPHONE
    NSDictionary *complete = @{ NSFileProtectionKey: NSFileProtectionComplete };
    for (NSString *suffix in @[@"", @"-journal"])
        [[NSFileManager defaultManager] setAttributes:complete ofItemAtPath:[_path stringByAppendingString:suffix] error:NULL];
#endif
}

- (BOOL)openAtPath:(NSString *)path {
    _path = [path copy];
    if (![self openFile:path]) return NO;
    [self protectFiles];
    if (![self createSchema]) return NO;
    sqlite3_exec(_db, "PRAGMA secure_delete = ON", NULL, NULL, NULL);   // Gelöschtes mit Nullen überschreiben
    return YES;
}

// Löscht die Datenbank samt Journal und legt sie leer neu an (Zurücksetzen).
// Vorher leeren (secure_delete überschreibt) und die Datei mit Nullen füllen: ohne Hardware-
// Verschlüsselung (iPod 2G) ließe sich ein bloß entferntes File sonst forensisch zurückholen.
- (BOOL)destroyAndReopen {
    [self setDataKey:nil];
    sqlite3_exec(_db, "DELETE FROM vault; DELETE FROM signal; DELETE FROM messages; DELETE FROM contacts;"
                      "DELETE FROM outbox; DELETE FROM profile; DELETE FROM identity;", NULL, NULL, NULL);
    sqlite3_close(_db); _db = NULL;
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *suffix in @[@"", @"-journal", @"-wal", @"-shm"]) {
        NSString *file = [_path stringByAppendingString:suffix];
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:file];
        unsigned long long size = [[fm attributesOfItemAtPath:file error:NULL] fileSize];
        if (h && size) { [h writeData:[NSMutableData dataWithLength:(NSUInteger)size]]; [h synchronizeFile]; [h closeFile]; }
        [fm removeItemAtPath:file error:NULL];
    }
    return [self openAtPath:_path];
}

#pragma mark - Profil

- (MeshProfile *)loadProfile {
    NSString *n = nil, *a = nil, *p = nil;
    sqlite3_stmt *st = [self prepare:"SELECT name, about, pic FROM profile WHERE id=1"];
    if (st && sqlite3_step(st) == SQLITE_ROW) {
        n = [self open:columnText(st, 0) context:profileContext("name")];
        a = [self open:columnText(st, 1) context:profileContext("about")];
        p = [self open:columnText(st, 2) context:profileContext("pic")];
    }
    sqlite3_finalize(st);
    MeshProfile *profile = [[MeshProfile alloc] init];
    profile.name = n ?: @""; profile.about = a ?: @""; profile.picture = p ?: @"";
    return profile;
}

- (BOOL)saveProfile:(MeshProfile *)profile {
    NSString *n = [self seal:profile.name context:profileContext("name")], *a = [self seal:profile.about context:profileContext("about")],
             *p = [self seal:profile.picture context:profileContext("pic")];
    if (!n || !a || !p) return NO;
    sqlite3_stmt *st = [self prepare:"INSERT OR REPLACE INTO profile(id,name,about,pic) VALUES(1,?,?,?)"];
    if (!st) return NO;
    bindText(st, 1, n); bindText(st, 2, a); bindText(st, 3, p);
    BOOL ok = sqlite3_step(st) == SQLITE_DONE;
    sqlite3_finalize(st);
    return ok;
}

#pragma mark - Kontakte

// Legt den Kontakt an oder ergänzt ihn. Verifizierung und Profil bleiben erhalten,
// "angenommen" wird nie zurückgenommen.
- (void)upsertContact:(NSString *)pubkeyHex name:(NSString *)name accepted:(BOOL)accepted {
    sqlite3_stmt *st = [self prepare:"INSERT OR IGNORE INTO contacts(pubkey, name, accepted) VALUES(?, '', ?)"];
    if (st) {
        bindText(st, 1, pubkeyHex);
        sqlite3_bind_int(st, 2, accepted ? 1 : 0);
        sqlite3_step(st);
        sqlite3_finalize(st);
    }
    NSString *sealed = name.length ? [self seal:name context:contactContext("name", pubkeyHex)] : nil;
    if (sealed && (st = [self prepare:"UPDATE contacts SET name=? WHERE pubkey=?"])) {
        bindText(st, 1, sealed); bindText(st, 2, pubkeyHex);
        sqlite3_step(st);
        sqlite3_finalize(st);
    }
    if (accepted) [self setAccepted:pubkeyHex];
}

- (void)setAccepted:(NSString *)pubkeyHex { [self run:"UPDATE contacts SET accepted=1 WHERE pubkey=?" text:pubkeyHex]; }

- (BOOL)isAccepted:(NSString *)pubkeyHex {
    return [self exists:"SELECT 1 FROM contacts WHERE pubkey=? AND accepted=1" text:pubkeyHex];
}

- (int)receivedCount:(NSString *)pubkeyHex bytes:(long long *)bytes {
    sqlite3_stmt *st = [self prepare:"SELECT COUNT(*), COALESCE(SUM(bytes),0) FROM messages WHERE chat=? AND from_me=0"];
    int n = 0; long long b = 0;
    if (st) {
        bindText(st, 1, pubkeyHex);
        if (sqlite3_step(st) == SQLITE_ROW) { n = sqlite3_column_int(st, 0); b = sqlite3_column_int64(st, 1); }
        sqlite3_finalize(st);
    }
    if (bytes) *bytes = b;
    return n;
}

- (NSArray *)acceptedContactPubkeys {
    NSMutableArray *out = [NSMutableArray array];
    sqlite3_stmt *st = [self prepare:"SELECT pubkey FROM contacts WHERE accepted=1"];
    while (st && sqlite3_step(st) == SQLITE_ROW) { NSString *p = columnText(st, 0); if (p) [out addObject:p]; }
    sqlite3_finalize(st);
    return out;
}

- (NSArray *)requestPubkeys:(NSUInteger)limit {
    NSMutableArray *out = [NSMutableArray array];
    sqlite3_stmt *st = [self prepare:"SELECT pubkey FROM contacts c WHERE accepted=0 AND pubkey NOT IN (SELECT pubkey FROM blocked) "
                                     "ORDER BY (SELECT MAX(ts) FROM messages WHERE chat=c.pubkey) DESC LIMIT ?"];
    if (st) sqlite3_bind_int64(st, 1, (sqlite3_int64)limit);
    while (st && sqlite3_step(st) == SQLITE_ROW) { NSString *p = columnText(st, 0); if (p) [out addObject:p]; }
    sqlite3_finalize(st);
    return out;
}

// Kontakt mit allen Nachrichten löschen. Die Event-IDs kommen in die Tombstone-Tabelle, damit
// Relays dieselben Nachrichten nicht erneut einspielen.
- (BOOL)deleteContact:(NSString *)pubkeyHex {
    BOOL ok = sqlite3_exec(_db, "BEGIN", NULL, NULL, NULL) == SQLITE_OK
        && [self run:"INSERT OR IGNORE INTO deleted(event_id) SELECT event_id FROM messages WHERE chat=? AND event_id IS NOT NULL" text:pubkeyHex]
        && [self run:"DELETE FROM outbox WHERE event_id IN (SELECT event_id FROM messages WHERE chat=?)" text:pubkeyHex]
        && [self run:"DELETE FROM messages WHERE chat=?" text:pubkeyHex]
        && [self run:"DELETE FROM contacts WHERE pubkey=?" text:pubkeyHex]
        && [self run:"DELETE FROM signal WHERE key='s.' || ?1 OR key='id.' || ?1" text:pubkeyHex];
    if (ok && sqlite3_exec(_db, "COMMIT", NULL, NULL, NULL) == SQLITE_OK) return YES;
    sqlite3_exec(_db, "ROLLBACK", NULL, NULL, NULL);
    return NO;
}

- (void)blockContact:(NSString *)pubkeyHex {
    [self deleteContact:pubkeyHex];
    [self run:"INSERT OR IGNORE INTO blocked(pubkey) VALUES(?)" text:pubkeyHex];
}

- (void)pruneTombstonesKeeping:(int)count {
    char sql[128];
    snprintf(sql, sizeof(sql), "DELETE FROM deleted WHERE rowid <= (SELECT MAX(rowid) FROM deleted) - %d", count);
    sqlite3_exec(_db, sql, NULL, NULL, NULL);
}

- (void)unblockContact:(NSString *)pubkeyHex {
    [self run:"DELETE FROM blocked WHERE pubkey=?" text:pubkeyHex];
}

- (BOOL)isBlocked:(NSString *)pubkeyHex {
    return [self exists:"SELECT 1 FROM blocked WHERE pubkey=? LIMIT 1" text:pubkeyHex];
}

// Ältester nicht angenommener Kontakt (zuerst angelegt), wird bei Platzmangel verdrängt.
- (NSString *)oldestUnacceptedContact {
    sqlite3_stmt *st = [self prepare:"SELECT pubkey FROM contacts WHERE accepted=0 ORDER BY rowid LIMIT 1"];
    NSString *pk = (st && sqlite3_step(st) == SQLITE_ROW) ? columnText(st, 0) : nil;
    sqlite3_finalize(st);
    return pk;
}

- (long long)unacceptedBytes {
    sqlite3_stmt *st = [self prepare:"SELECT COALESCE(SUM(m.bytes),0) FROM messages m JOIN contacts c ON c.pubkey=m.chat WHERE c.accepted=0"];
    long long b = (st && sqlite3_step(st) == SQLITE_ROW) ? sqlite3_column_int64(st, 0) : 0;
    sqlite3_finalize(st);
    return b;
}

- (int)unacceptedContactCount {
    sqlite3_stmt *st = [self prepare:"SELECT COUNT(*) FROM contacts WHERE accepted=0"];
    int n = (st && sqlite3_step(st) == SQLITE_ROW) ? sqlite3_column_int(st, 0) : 0;
    sqlite3_finalize(st);
    return n;
}

- (BOOL)isContact:(NSString *)pubkeyHex {
    return [self exists:"SELECT 1 FROM contacts WHERE pubkey=? LIMIT 1" text:pubkeyHex];
}

- (BOOL)isVerified:(NSString *)pubkeyHex {
    return [self exists:"SELECT 1 FROM contacts WHERE pubkey=? AND verified=1" text:pubkeyHex];
}

- (void)setVerified:(NSString *)pubkeyHex verified:(BOOL)v {
    sqlite3_stmt *st = [self prepare:"UPDATE contacts SET verified=? WHERE pubkey=?"];
    if (!st) return;
    sqlite3_bind_int(st, 1, v ? 1 : 0);
    bindText(st, 2, pubkeyHex);
    sqlite3_step(st);
    sqlite3_finalize(st);
}

// Ein entschlüsseltes Feld eines Kontakts (column: name, pname oder pic).
- (NSString *)contact:(NSString *)pubkeyHex column:(const char *)column {
    NSString *sql = [NSString stringWithFormat:@"SELECT %s FROM contacts WHERE pubkey=?", column];
    sqlite3_stmt *st = [self prepare:sql.UTF8String];
    NSString *out = nil;
    if (st) {
        bindText(st, 1, pubkeyHex);
        if (sqlite3_step(st) == SQLITE_ROW) out = [self open:columnText(st, 0) context:contactContext(column, pubkeyHex)];
        sqlite3_finalize(st);
    }
    return out.length ? out : nil;
}

- (NSString *)nameForContact:(NSString *)pubkeyHex        { return [self contact:pubkeyHex column:"name"]; }
- (NSString *)picForContact:(NSString *)pubkeyHex         { return [self contact:pubkeyHex column:"pic"]; }
- (NSString *)profileNameForContact:(NSString *)pubkeyHex { return [self contact:pubkeyHex column:"pname"]; }

- (void)forgetProfileTimeOf:(NSString *)pubkeyHex {
    [self run:"UPDATE contacts SET pts=0 WHERE pubkey=?" text:pubkeyHex];
}

- (BOOL)setContactProfile:(NSString *)pubkeyHex pname:(NSString *)pname pic:(NSString *)pic createdAt:(long long)ts {
    return [self setContactProfile:pubkeyHex pname:pname pic:pic createdAt:ts sameAgain:NO];
}
- (BOOL)setContactProfile:(NSString *)pubkeyHex pname:(NSString *)pname pic:(NSString *)pic createdAt:(long long)ts sameAgain:(BOOL)same {
    NSString *n = [self seal:pname context:contactContext("pname", pubkeyHex)];
    NSString *p = [self seal:pic context:contactContext("pic", pubkeyHex)];
    if (!n || !p) return NO;
    sqlite3_stmt *st = [self prepare:same ? "UPDATE contacts SET pname=?, pic=?, pts=? WHERE pubkey=? AND pts <= ?"
                                          : "UPDATE contacts SET pname=?, pic=?, pts=? WHERE pubkey=? AND pts < ?"];
    if (!st) return NO;
    bindText(st, 1, n); bindText(st, 2, p); sqlite3_bind_int64(st, 3, ts);
    bindText(st, 4, pubkeyHex); sqlite3_bind_int64(st, 5, ts);
    BOOL changed = sqlite3_step(st) == SQLITE_DONE && sqlite3_changes(_db) > 0;
    sqlite3_finalize(st);
    return changed;
}

#pragma mark - Nachrichten

- (BOOL)hasEventId:(NSString *)eventId {
    return eventId.length && [self exists:"SELECT 1 FROM messages WHERE event_id=? LIMIT 1" text:eventId];
}

- (BOOL)isDeleted:(NSString *)eventId {
    return eventId.length && [self exists:"SELECT 1 FROM deleted WHERE event_id=? LIMIT 1" text:eventId];
}

- (long long)insertMessage:(MeshMessage *)m chat:(NSString *)chat content:(NSString *)content {
    NSString *eventId = m.eventId.length ? m.eventId : nil;
    if (eventId && [self isDeleted:eventId]) return 0;   // vom Nutzer gelöscht -> nicht wieder einfügen
    MeshPayloadKind kind = m.kind == MeshPayloadNotice ? MeshPayloadNotice : [MeshPayload kindOf:content];
    int secs = kind == MeshPayloadVoice ? [MeshPayload parse:content].seconds : 0;
    NSString *sealed = [self seal:content context:messageContext(chat, (int)kind, secs, m.fromMe, eventId)];
    if (!sealed) return 0;
    sqlite3_stmt *st = [self prepare:"INSERT OR IGNORE INTO messages(chat, from_me, content, ts, event_id, kind, secs, bytes,"
                                      " status, cmid, reply_to, timer, expires) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)"];
    if (!st) return 0;
    bindText(st, 1, chat);
    sqlite3_bind_int (st, 2, m.fromMe ? 1 : 0);
    bindText(st, 3, sealed);
    sqlite3_bind_int64(st, 4, m.ts);
    bindText(st, 5, eventId);
    sqlite3_bind_int (st, 6, (int)kind);
    sqlite3_bind_int (st, 7, secs);
    sqlite3_bind_int64(st, 8, (sqlite3_int64)[content lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
    sqlite3_bind_int (st, 9, (int)m.status);
    bindText(st, 10, m.cmid.length ? m.cmid : nil);
    bindText(st, 11, m.replyTo.length ? m.replyTo : nil);
    sqlite3_bind_int (st, 12, MAX(0, m.timer));
    sqlite3_bind_int64(st, 13, m.expiresAt);
    BOOL ok = sqlite3_step(st) == SQLITE_DONE && sqlite3_changes(_db) > 0;
    sqlite3_finalize(st);
    if (!ok) return 0;
    m.rowId = sqlite3_last_insert_rowid(_db);
    m.kind = kind;
    return m.rowId;
}

- (void)setImageWidth:(int)width height:(int)height ofMessage:(long long)rowId {
    sqlite3_stmt *st = [self prepare:"UPDATE messages SET width=?, height=? WHERE rowid=?"];
    if (!st) return;
    sqlite3_bind_int(st, 1, width);
    sqlite3_bind_int(st, 2, height);
    sqlite3_bind_int64(st, 3, rowId);
    sqlite3_step(st);
    sqlite3_finalize(st);
}

- (long long)newestReceivedTime {
    sqlite3_stmt *st = [self prepare:"SELECT COALESCE(MAX(ts),0) FROM messages WHERE from_me=0"];
    long long ts = (st && sqlite3_step(st) == SQLITE_ROW) ? sqlite3_column_int64(st, 0) : 0;
    sqlite3_finalize(st);
    return ts;
}

// Gibt YES zurück, wenn sich der Status tatsächlich änderte (sonst kein UI-Reload nötig).
- (BOOL)markDelivered:(NSString *)eventId {
    if (!eventId.length) return NO;
    [self run:"DELETE FROM outbox WHERE event_id=?" text:eventId];
    BOOL changed = [self run:"UPDATE messages SET status=1 WHERE event_id=? AND status!=1" text:eventId] && sqlite3_changes(_db) > 0;
    // "Ab Gesehen": die Uhr einer eigenen Nachricht startet, sobald sie unterwegs ist.
    sqlite3_stmt *st = changed ? [self prepare:"UPDATE messages SET expires=?+timer WHERE event_id=? AND timer>0 AND expires=0"] : NULL;
    if (st) {
        sqlite3_bind_int64(st, 1, MeshNow());
        bindText(st, 2, eventId);
        sqlite3_step(st);
        sqlite3_finalize(st);
    }
    return changed;
}

// Eine Nachricht löschen. Tombstone: merken, damit ein Relay sie nicht wieder einschleust.
- (void)deleteMessage:(long long)rowId {
    sqlite3_stmt *st = [self prepare:"SELECT event_id FROM messages WHERE rowid=?"];
    if (!st) return;
    sqlite3_bind_int64(st, 1, rowId);
    NSString *eventId = sqlite3_step(st) == SQLITE_ROW ? columnText(st, 0) : nil;
    sqlite3_finalize(st);
    if (eventId.length) {
        [self run:"INSERT OR IGNORE INTO deleted(event_id) VALUES(?)" text:eventId];
        [self run:"DELETE FROM outbox WHERE event_id=?" text:eventId];
    }
    if ((st = [self prepare:"DELETE FROM messages WHERE rowid=?"])) {
        sqlite3_bind_int64(st, 1, rowId);
        sqlite3_step(st);
        sqlite3_finalize(st);
    }
}

// Inhalt für Listen: Text entschlüsselt, Medien nur als Marker (die Daten holt contentOfMessage:).
- (NSString *)listContentChat:(NSString *)chat kind:(int)kind secs:(int)secs fromMe:(BOOL)fromMe
                       eventId:(NSString *)eventId stored:(NSString *)stored {
    NSString *marker = [MeshPayload markerForKind:kind seconds:secs];
    return marker ?: [self open:stored context:messageContext(chat, kind, secs, fromMe, eventId)] ?: @"";
}

// Spalten für MeshMessage, in der Reihenfolge von messageFromRow.
// Ganz geladen werden nur kleine Arten (Text, Hinweis, Kontaktkarte); die Zahlen sind MeshPayloadKind.
_Static_assert(MeshPayloadText == 0 && MeshPayloadNotice == 4 && MeshPayloadContact == 5, "kind IN (0,4,5) anpassen");
#define MESSAGE_COLUMNS "kind, secs, CASE WHEN kind IN (0,4,5) THEN content END, from_me, ts, event_id, status, rowid, " \
                        "width, height, cmid, reply_to, react_mine, react_peer, timer, expires"

- (MeshMessage *)messageFromRow:(sqlite3_stmt *)st chat:(NSString *)chat {
    MeshMessage *m = [[MeshMessage alloc] init];
    m.kind    = sqlite3_column_int(st, 0);
    m.fromMe  = sqlite3_column_int(st, 3) != 0;
    m.ts      = sqlite3_column_int64(st, 4);
    m.eventId = columnText(st, 5);
    m.content = [self listContentChat:chat kind:(int)m.kind secs:sqlite3_column_int(st, 1)
                               fromMe:m.fromMe eventId:m.eventId stored:columnText(st, 2)];
    m.status  = sqlite3_column_int(st, 6);
    m.rowId   = sqlite3_column_int64(st, 7);
    m.width   = sqlite3_column_int(st, 8);
    m.height  = sqlite3_column_int(st, 9);
    m.cmid    = columnText(st, 10);
    m.replyTo = columnText(st, 11);
    m.reactMine = [self open:columnText(st, 12) context:reactionContext(chat, m.rowId, YES)];
    m.reactPeer = [self open:columnText(st, 13) context:reactionContext(chat, m.rowId, NO)];
    m.timer   = sqlite3_column_int(st, 14);
    m.expiresAt = sqlite3_column_int64(st, 15);
    return m;
}

- (NSArray *)messagesForChat:(NSString *)pubkeyHex {
    NSMutableArray *out = [NSMutableArray array];
    sqlite3_stmt *st = [self prepare:"SELECT " MESSAGE_COLUMNS " FROM messages WHERE chat=? ORDER BY ts ASC, rowid ASC"];
    if (!st) return out;
    bindText(st, 1, pubkeyHex);
    while (sqlite3_step(st) == SQLITE_ROW) [out addObject:[self messageFromRow:st chat:pubkeyHex]];
    sqlite3_finalize(st);
    return out;
}

- (MeshMessage *)messageWithKey:(NSString *)key chat:(NSString *)chat {
    if (!key.length) return nil;
    sqlite3_stmt *st = [self prepare:"SELECT " MESSAGE_COLUMNS " FROM messages WHERE chat=?1 AND (cmid=?2 OR event_id=?2) LIMIT 1"];
    if (!st) return nil;
    bindText(st, 1, chat);
    bindText(st, 2, key);
    MeshMessage *m = sqlite3_step(st) == SQLITE_ROW ? [self messageFromRow:st chat:chat] : nil;
    sqlite3_finalize(st);
    return m;
}

- (NSString *)contentOfMessage:(long long)rowId {
    sqlite3_stmt *st = [self prepare:"SELECT content, chat, kind, secs, from_me, event_id FROM messages WHERE rowid=?"];
    NSString *out = nil;
    if (!st) return nil;
    sqlite3_bind_int64(st, 1, rowId);
    if (sqlite3_step(st) == SQLITE_ROW)
        out = [self open:columnText(st, 0) context:messageContext(columnText(st, 1), sqlite3_column_int(st, 2), sqlite3_column_int(st, 3),
                                                                  sqlite3_column_int(st, 4) != 0, columnText(st, 5))];
    sqlite3_finalize(st);
    return out;
}

- (NSArray *)chatList {
    NSMutableArray *out = [NSMutableArray array];
    // Letzte Nachricht je Chat; Medien nur als Marker.
    sqlite3_stmt *st = [self prepare:
        "SELECT m.chat, m.kind, m.secs, CASE WHEN m.kind IN (0,4,5) THEN m.content END, m.from_me, m.ts, m.event_id, "
        "       c.name, c.pname, COALESCE(c.accepted, 0) FROM messages m "
        "JOIN (SELECT chat, MAX(ts) mts FROM messages GROUP BY chat) x ON m.chat=x.chat AND m.ts=x.mts "
        "LEFT JOIN contacts c ON c.pubkey=m.chat "
        "GROUP BY m.chat ORDER BY m.ts DESC"];
    while (st && sqlite3_step(st) == SQLITE_ROW) {
        MeshChat *chat = [[MeshChat alloc] init];
        chat.pubkey = columnText(st, 0) ?: @"";
        chat.fromMe = sqlite3_column_int(st, 4) != 0;
        NSString *c = [self listContentChat:chat.pubkey kind:sqlite3_column_int(st, 1) secs:sqlite3_column_int(st, 2)
                                     fromMe:chat.fromMe eventId:columnText(st, 6) stored:columnText(st, 3)];
        chat.lastContent = MeshTruncate(c, 200);
        chat.ts     = sqlite3_column_int64(st, 5);
        chat.ownName = [self open:columnText(st, 7) context:contactContext("name", chat.pubkey)];
        chat.profileName = [self open:columnText(st, 8) context:contactContext("pname", chat.pubkey)];
        chat.unknown = sqlite3_column_int(st, 9) == 0;
        chat.lastKind = sqlite3_column_int(st, 1);
        [out addObject:chat];
    }
    sqlite3_finalize(st);
    return out;
}

@end
