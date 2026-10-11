#import "MeshStore+Outbox.h"
#import "MeshStore+Internal.h"
#import "MeshMessage.h"

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

- (NSArray *)queuedEvents {
    NSMutableArray *out = [NSMutableArray array];
    // Begrenzt: jede neue Verbindung entsiegelt die Warteschlange; mehr wartet beim nächsten Mal.
    sqlite3_stmt *st = [self prepare:"SELECT event_id, event FROM outbox ORDER BY created LIMIT 50"];
    while (st && sqlite3_step(st) == SQLITE_ROW) {
        NSString *json = [self open:columnText(st, 1) context:outboxContext(columnText(st, 0) ?: @"")];
        if (json) [out addObject:json];
    }
    sqlite3_finalize(st);
    return out;
}

- (BOOL)expireQueuedBefore:(long long)time {
    sqlite3_stmt *st = [self prepare:"UPDATE messages SET status=?1 WHERE status=?2 "
                                      "AND event_id IN (SELECT event_id FROM outbox WHERE created < ?3)"];
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
    return changed;
}

@end
