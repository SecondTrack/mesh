#import "MeshStore+Outbox.h"
#import "MeshStore+Internal.h"
#import "MeshMessage.h"
#import "MeshTime.h"

static NSString *outboxContext(NSString *eventId) {
    return [@"outbox.event|" stringByAppendingString:eventId];
}

@implementation MeshStore (Outbox)

- (BOOL)queueEvent:(NSString *)json eventId:(NSString *)eventId created:(long long)created {
    NSString *sealed = eventId.length ? [self seal:json context:outboxContext(eventId)] : nil;
    if (!sealed) return NO;
    sqlite3_stmt *st = [self prepare:"INSERT OR REPLACE INTO outbox(event_id, event, created) VALUES(?,?,?)"];
    if (!st) return NO;
    bindText(st, 1, eventId);
    bindText(st, 2, sealed);
    sqlite3_bind_int64(st, 3, created);
    BOOL ok = sqlite3_step(st) == SQLITE_DONE;
    sqlite3_finalize(st);
    return ok;
}

- (NSArray *)queuedEvents { return [self queuedEventsExcluding:nil maxBytes:MeshOutboxMaxBytes]; }

// Begrenzt nach Zeilen und Bytes (versiegelte Länge, ohne zu entsiegeln): jede neue Verbindung lädt die
// Warteschlange; 50 Gruppen-Medien auf einmal ließen den A4 (256 MB) vom System beenden. Mindestens eins.
- (NSArray *)queuedEventsExcluding:(NSSet *)eventIds maxBytes:(NSUInteger)maxBytes {
    NSMutableArray *out = [NSMutableArray array];
    sqlite3_stmt *st = [self prepare:"SELECT event_id, length(event) FROM outbox ORDER BY created, rowid"];
    NSMutableArray *ids = [NSMutableArray array];
    unsigned long long bytes = 0;
    while (st && ids.count < 50 && sqlite3_step(st) == SQLITE_ROW) {
        NSString *eid = columnText(st, 0);
        if (!eid || [eventIds containsObject:eid]) continue;
        unsigned long long len = (unsigned long long)sqlite3_column_int64(st, 1);
        if (ids.count && bytes + len > maxBytes) break;
        bytes += len;
        [ids addObject:eid];
    }
    sqlite3_finalize(st);
    for (NSString *eid in ids) @autoreleasepool {
        sqlite3_stmt *q = [self prepare:"SELECT event FROM outbox WHERE event_id=?"];
        if (!q) break;
        bindText(q, 1, eid);
        NSString *json = sqlite3_step(q) == SQLITE_ROW ? [self open:columnText(q, 0) context:outboxContext(eid)] : nil;
        sqlite3_finalize(q);
        if (json) [out addObject:json];
    }
    return out;
}

#pragma mark - Gruppen-Fan-out

- (BOOL)addFanout:(NSString *)eventId message:(long long)rowId {
    if (!eventId.length || rowId <= 0) return NO;
    sqlite3_stmt *st = [self prepare:"INSERT OR REPLACE INTO fanout(event_id, message_rowid) VALUES(?,?)"];
    if (!st) return NO;
    bindText(st, 1, eventId);
    sqlite3_bind_int64(st, 2, rowId);
    BOOL ok = sqlite3_step(st) == SQLITE_DONE;
    sqlite3_finalize(st);
    return ok;
}

// Ein Relay hat eine Kopie angenommen: Nachricht zugestellt (zwei Haken, sobald irgendeine Kopie da ist).
- (BOOL)markFanoutDelivered:(NSString *)eventId {
    if (!eventId.length) return NO;
    sqlite3_stmt *st = [self prepare:"SELECT message_rowid FROM fanout WHERE event_id=?"];
    if (!st) return NO;
    bindText(st, 1, eventId);
    long long rowId = sqlite3_step(st) == SQLITE_ROW ? sqlite3_column_int64(st, 0) : 0;
    sqlite3_finalize(st);
    if (!rowId) return NO;
    [self run:"DELETE FROM fanout WHERE event_id=?" text:eventId];
    [self run:"DELETE FROM outbox WHERE event_id=?" text:eventId];
    if (!(st = [self prepare:"UPDATE messages SET status=1 WHERE rowid=? AND status!=1"])) return NO;
    sqlite3_bind_int64(st, 1, rowId);
    BOOL changed = sqlite3_step(st) == SQLITE_DONE && sqlite3_changes(self.db) > 0;
    sqlite3_finalize(st);
    // "Ab Gesehen": die Uhr startet, sobald sie unterwegs ist (wie markMessageDelivered)
    if (changed && (st = [self prepare:"UPDATE messages SET expires=?+timer WHERE rowid=? AND timer>0 AND expires=0"])) {
        sqlite3_bind_int64(st, 1, MeshNow());
        sqlite3_bind_int64(st, 2, rowId);
        sqlite3_step(st);
        sqlite3_finalize(st);
    }
    return changed;
}

// Gruppe verlassen/entfernt/aufgelöst: noch nicht hinausgegangene Kopien eigener Nachrichten verwerfen;
// Nachrichten, von denen keine Kopie angekommen ist, gelten als nicht zugestellt.
- (void)dropQueuedCopiesInChat:(NSString *)chat {
    if (!chat.length) return;
    BOOL ok = sqlite3_exec(self.db, "BEGIN", NULL, NULL, NULL) == SQLITE_OK;
    sqlite3_stmt *st = ok ? [self prepare:"UPDATE messages SET status=?2 WHERE chat=?1 AND from_me=1 AND status=?3 "
                                           "AND rowid IN (SELECT message_rowid FROM fanout)"] : NULL;
    if ((ok = st != NULL)) {
        bindText(st, 1, chat);
        sqlite3_bind_int(st, 2, MeshMessageFailed);
        sqlite3_bind_int(st, 3, MeshMessageSending);
        ok = sqlite3_step(st) == SQLITE_DONE;
        sqlite3_finalize(st);
    }
    ok = ok && [self run:"DELETE FROM outbox WHERE event_id IN (SELECT event_id FROM fanout WHERE message_rowid IN "
                         "(SELECT rowid FROM messages WHERE chat=?1))" text:chat]
            && [self run:"DELETE FROM fanout WHERE message_rowid IN (SELECT rowid FROM messages WHERE chat=?1)" text:chat];
    if (ok && sqlite3_exec(self.db, "COMMIT", NULL, NULL, NULL) == SQLITE_OK) return;
    sqlite3_exec(self.db, "ROLLBACK", NULL, NULL, NULL);
}

- (BOOL)hasMessageRow:(long long)rowId {
    sqlite3_stmt *st = [self prepare:"SELECT 1 FROM messages WHERE rowid=?"];
    if (!st) return NO;
    sqlite3_bind_int64(st, 1, rowId);
    BOOL found = sqlite3_step(st) == SQLITE_ROW;
    sqlite3_finalize(st);
    return found;
}

- (BOOL)expireQueuedBefore:(long long)time {
    // Gruppe: fehlgeschlagen erst, wenn keine Kopie angekommen ist (sonst steht status schon auf 1)
    sqlite3_stmt *st = [self prepare:"UPDATE messages SET status=?1 WHERE status=?2 "
                                      "AND (event_id IN (SELECT event_id FROM outbox WHERE created < ?3) "
                                      "OR rowid IN (SELECT f.message_rowid FROM fanout f JOIN outbox o ON o.event_id=f.event_id WHERE o.created < ?3))"];
    if (!st) return NO;
    sqlite3_bind_int(st, 1, MeshMessageFailed);
    sqlite3_bind_int(st, 2, MeshMessageSending);
    sqlite3_bind_int64(st, 3, time);
    BOOL changed = sqlite3_step(st) == SQLITE_DONE && sqlite3_changes(self.db) > 0;
    sqlite3_finalize(st);
    st = [self prepare:"DELETE FROM outbox WHERE created < ?"];
    if (st) {
        sqlite3_bind_int64(st, 1, time);
        sqlite3_step(st);
        sqlite3_finalize(st);
    }
    sqlite3_exec(self.db, "DELETE FROM fanout WHERE event_id NOT IN (SELECT event_id FROM outbox)", NULL, NULL, NULL);
    return changed;
}

@end
