#import "MeshStore+Chat.h"
#import "MeshStore+Internal.h"

@implementation MeshStore (Chat)

- (BOOL)setReaction:(NSString *)emoji mine:(BOOL)mine key:(NSString *)key chat:(NSString *)chat {
    if (!key.length) return NO;
    sqlite3_stmt *st = [self prepare:"SELECT rowid FROM messages WHERE chat=?1 AND (cmid=?2 OR event_id=?2)"];
    if (!st) return NO;
    bindText(st, 1, chat);
    bindText(st, 2, key);
    NSMutableArray *rows = [NSMutableArray array];
    while (sqlite3_step(st) == SQLITE_ROW) [rows addObject:@(sqlite3_column_int64(st, 0))];
    sqlite3_finalize(st);

    const char *sql = mine ? "UPDATE messages SET react_mine=? WHERE rowid=?" : "UPDATE messages SET react_peer=? WHERE rowid=?";
    for (NSNumber *row in rows) {
        NSString *sealed = emoji.length ? [self seal:emoji context:reactionContext(chat, row.longLongValue, mine)] : nil;
        if (emoji.length && !sealed) return NO;
        if (!(st = [self prepare:sql])) return NO;
        bindText(st, 1, sealed);
        sqlite3_bind_int64(st, 2, row.longLongValue);
        sqlite3_step(st);
        sqlite3_finalize(st);
    }
    return rows.count > 0;
}

- (void)rememberProcessed:(NSString *)eventId {
    if (eventId.length) [self run:"INSERT OR IGNORE INTO deleted(event_id) VALUES(?)" text:eventId];
}

// Tombstones und Warteschlange für die ausgewählten Zeilen, dann die Zeilen selbst.
- (BOOL)deleteMessagesWhere:(const char *)condition bind:(void (^)(sqlite3_stmt *))bind {
    NSString *tomb = [NSString stringWithFormat:@"INSERT OR IGNORE INTO deleted(event_id) SELECT event_id FROM messages WHERE event_id IS NOT NULL AND %s", condition];
    NSString *outbox = [NSString stringWithFormat:@"DELETE FROM outbox WHERE event_id IN (SELECT event_id FROM messages WHERE %s)", condition];
    NSString *rows = [NSString stringWithFormat:@"DELETE FROM messages WHERE %s", condition];
    BOOL ok = sqlite3_exec(self.db, "BEGIN", NULL, NULL, NULL) == SQLITE_OK;
    for (NSString *sql in @[tomb, outbox, rows]) {
        sqlite3_stmt *st = ok ? [self prepare:sql.UTF8String] : NULL;
        if (!st) { ok = NO; break; }
        bind(st);
        ok = sqlite3_step(st) == SQLITE_DONE;
        sqlite3_finalize(st);
    }
    int deleted = sqlite3_changes(self.db);   // der letzten Anweisung, also der Zeilen
    if (ok && sqlite3_exec(self.db, "COMMIT", NULL, NULL, NULL) == SQLITE_OK) return deleted > 0;
    sqlite3_exec(self.db, "ROLLBACK", NULL, NULL, NULL);
    return NO;
}

- (BOOL)deletePeerMessageWithKey:(NSString *)key chat:(NSString *)chat {
    if (!key.length) return NO;
    return [self deleteMessagesWhere:"chat=?1 AND from_me=0 AND (cmid=?2 OR event_id=?2)" bind:^(sqlite3_stmt *st) {
        bindText(st, 1, chat);
        bindText(st, 2, key);
    }];
}

- (BOOL)clearChat:(NSString *)chat at:(long long)time {
    [self deleteMessagesWhere:"chat=?1" bind:^(sqlite3_stmt *st) { bindText(st, 1, chat); }];
    [self run:"INSERT OR IGNORE INTO chats(chat) VALUES(?)" text:chat];
    sqlite3_stmt *st = [self prepare:"UPDATE chats SET cleared=MAX(cleared, ?) WHERE chat=?"];
    if (!st) return NO;
    sqlite3_bind_int64(st, 1, time);
    bindText(st, 2, chat);
    BOOL ok = sqlite3_step(st) == SQLITE_DONE;
    sqlite3_finalize(st);
    return ok;
}

- (long long)clearedAt:(NSString *)chat {
    sqlite3_stmt *st = [self prepare:"SELECT cleared FROM chats WHERE chat=?"];
    if (!st) return 0;
    bindText(st, 1, chat);
    long long t = sqlite3_step(st) == SQLITE_ROW ? sqlite3_column_int64(st, 0) : 0;
    sqlite3_finalize(st);
    return t;
}

- (int)timerForChat:(NSString *)chat fromSent:(BOOL *)fromSent {
    sqlite3_stmt *st = [self prepare:"SELECT timer, timer_mode FROM chats WHERE chat=?"];
    int seconds = 0; BOOL sent = NO;
    if (st) {
        bindText(st, 1, chat);
        if (sqlite3_step(st) == SQLITE_ROW) { seconds = sqlite3_column_int(st, 0); sent = sqlite3_column_int(st, 1) != 0; }
        sqlite3_finalize(st);
    }
    if (fromSent) *fromSent = sent;
    return seconds;
}

- (void)setTimer:(int)seconds fromSent:(BOOL)fromSent chat:(NSString *)chat {
    [self run:"INSERT OR IGNORE INTO chats(chat) VALUES(?)" text:chat];
    sqlite3_stmt *st = [self prepare:"UPDATE chats SET timer=?, timer_mode=? WHERE chat=?"];
    if (!st) return;
    sqlite3_bind_int(st, 1, MAX(0, seconds));
    sqlite3_bind_int(st, 2, fromSent ? 1 : 0);
    bindText(st, 3, chat);
    sqlite3_step(st);
    sqlite3_finalize(st);
}

- (void)startTimersInChat:(NSString *)chat now:(long long)now {
    sqlite3_stmt *st = [self prepare:"UPDATE messages SET expires=?+timer WHERE chat=? AND from_me=0 AND timer>0 AND expires=0"];
    if (!st) return;
    sqlite3_bind_int64(st, 1, now);
    bindText(st, 2, chat);
    sqlite3_step(st);
    sqlite3_finalize(st);
}

- (int)deleteExpiredAt:(long long)now {
    int before = 0;
    sqlite3_stmt *count = [self prepare:"SELECT COUNT(*) FROM messages WHERE expires>0 AND expires<=?"];
    if (count) {
        sqlite3_bind_int64(count, 1, now);
        if (sqlite3_step(count) == SQLITE_ROW) before = sqlite3_column_int(count, 0);
        sqlite3_finalize(count);
    }
    if (!before) return 0;
    [self deleteMessagesWhere:"expires>0 AND expires<=?1" bind:^(sqlite3_stmt *st) { sqlite3_bind_int64(st, 1, now); }];
    return before;
}

- (long long)nextExpiry {
    sqlite3_stmt *st = [self prepare:"SELECT COALESCE(MIN(expires),0) FROM messages WHERE expires>0"];
    long long t = (st && sqlite3_step(st) == SQLITE_ROW) ? sqlite3_column_int64(st, 0) : 0;
    sqlite3_finalize(st);
    return t;
}

@end
