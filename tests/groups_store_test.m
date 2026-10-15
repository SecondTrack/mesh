// Umstellung einer Datenbank von 0.1.26 auf das Schema mit Gruppen und Team-Chat: neue Tabellen und
// Spalte kommen dazu, alles Vorhandene bleibt lesbar und unverändert. Dazu Gruppen-/Team-Speicher.
#import "MeshTest.h"
#import <sqlite3.h>
#import "MeshStore.h"
#import "MeshStore+Group.h"
#import "MeshStore+Chat.h"
#import "MeshStore+Outbox.h"
#import "MeshMessage.h"
#import "MeshPayload.h"
#import "MeshChat.h"
#import "MeshSeal.h"
#import "MeshTime.h"

// Schema von 0.1.26 (MeshStore+Migration createSchema, Stand vor den Gruppen), wie es nach dem ersten Öffnen dasteht.
static const char *kSchema0126 =
    "CREATE TABLE identity(id INTEGER PRIMARY KEY CHECK(id=1), seckey TEXT);"
    "CREATE TABLE vault(id INTEGER PRIMARY KEY CHECK(id=1), salt BLOB, iv BLOB, ct BLOB, pubkey TEXT, iters INTEGER,"
    "  peppered INTEGER NOT NULL DEFAULT 0, kdf INTEGER NOT NULL DEFAULT 0);"
    "CREATE TABLE contacts(pubkey TEXT PRIMARY KEY, name TEXT, verified INTEGER NOT NULL DEFAULT 0, pname TEXT, pic TEXT,"
    "  accepted INTEGER NOT NULL DEFAULT 1, pts INTEGER NOT NULL DEFAULT 0, bundle TEXT, about TEXT);"
    "CREATE TABLE profile(id INTEGER PRIMARY KEY CHECK(id=1), name TEXT, about TEXT, pic TEXT);"
    "CREATE TABLE messages(rowid INTEGER PRIMARY KEY AUTOINCREMENT, chat TEXT NOT NULL, from_me INTEGER NOT NULL,"
    "  content TEXT NOT NULL, ts INTEGER NOT NULL, event_id TEXT UNIQUE, status INTEGER NOT NULL DEFAULT 0,"
    "  kind INTEGER NOT NULL DEFAULT 0, secs INTEGER NOT NULL DEFAULT 0, bytes INTEGER NOT NULL DEFAULT 0,"
    "  width INTEGER NOT NULL DEFAULT 0, height INTEGER NOT NULL DEFAULT 0, cmid TEXT, reply_to TEXT, react_mine TEXT,"
    "  react_peer TEXT, timer INTEGER NOT NULL DEFAULT 0, expires INTEGER NOT NULL DEFAULT 0);"
    "CREATE INDEX idx_msg_chat ON messages(chat, ts);"
    "CREATE TABLE deleted(event_id TEXT PRIMARY KEY);"
    "CREATE TABLE blocked(pubkey TEXT PRIMARY KEY);"
    "CREATE TABLE outbox(event_id TEXT PRIMARY KEY, event TEXT NOT NULL, created INTEGER NOT NULL);"
    "CREATE TABLE chats(chat TEXT PRIMARY KEY, timer INTEGER NOT NULL DEFAULT 0, timer_mode INTEGER NOT NULL DEFAULT 0,"
    "  cleared INTEGER NOT NULL DEFAULT 0, read INTEGER NOT NULL DEFAULT 0);"
    "CREATE TABLE signal(key TEXT PRIMARY KEY, value TEXT NOT NULL);"
    "CREATE TABLE message_blobs(rowid INTEGER PRIMARY KEY, content TEXT NOT NULL);"
    "CREATE TRIGGER messages_blob_delete AFTER DELETE ON messages BEGIN DELETE FROM message_blobs WHERE rowid=old.rowid; END;"
    "CREATE TABLE meta(key TEXT PRIMARY KEY, value INTEGER NOT NULL);"
    "INSERT INTO meta VALUES('media_moved', 1);"
    "PRAGMA user_version = 3;";

static NSString *A64(char c) { return [@"" stringByPaddingToLength:64 withString:[NSString stringWithFormat:@"%c", c] startingAtIndex:0]; }

static BOOL hasColumn(sqlite3 *db, const char *table, const char *column) {
    char sql[128]; snprintf(sql, sizeof(sql), "PRAGMA table_info(%s)", table);
    sqlite3_stmt *st; BOOL found = NO;
    if (sqlite3_prepare_v2(db, sql, -1, &st, NULL) != SQLITE_OK) return NO;
    while (!found && sqlite3_step(st) == SQLITE_ROW) found = !strcmp((const char *)sqlite3_column_text(st, 1) ?: "", column);
    sqlite3_finalize(st);
    return found;
}

int main(void) {
    @autoreleasepool {
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"mesh-0126-%d.sqlite", getpid()]];
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        NSMutableData *key = [NSMutableData dataWithLength:32]; arc4random_buf(key.mutableBytes, 32);
        NSString *peer = A64('b');

        // 0.1.26 anlegen: Kontakt und Nachricht, versiegelt wie in 0.1.26 (Kontext ohne Absender)
        sqlite3 *db;
        sqlite3_open(path.UTF8String, &db);
        check(sqlite3_exec(db, kSchema0126, NULL, NULL, NULL) == SQLITE_OK, "0.1.26 schema created");
        NSString *ctx = [NSString stringWithFormat:@"messages.content|%@|0|0|0|%@", peer, A64('e')];
        NSString *sealed = [MeshSeal seal:@"Alte Nachricht" key:key context:ctx];
        NSString *ins = [NSString stringWithFormat:@"INSERT INTO contacts(pubkey, name, accepted) VALUES('%@', '', 1);"
                         "INSERT INTO messages(chat, from_me, content, ts, event_id, status, kind) VALUES('%@', 0, '%@', 1000, '%@', 1, 0);",
                         peer, peer, sealed, A64('e')];
        check(sqlite3_exec(db, ins.UTF8String, NULL, NULL, NULL) == SQLITE_OK, "0.1.26 data inserted");
        sqlite3_close(db);

        // 0.1.27 öffnet
        MeshStore *store = [MeshStore new];
        check([store openAtPath:path], "opens with new code");
        [store setDataKey:key];
        sqlite3 *raw;
        sqlite3_open(path.UTF8String, &raw);
        check(hasColumn(raw, "messages", "sender") && hasColumn(raw, "groups", "state") && hasColumn(raw, "group_invites", "at")
              && hasColumn(raw, "team", "ekey") && hasColumn(raw, "team_outbox", "event"), "new tables and column added");
        sqlite3_stmt *v;
        sqlite3_prepare_v2(raw, "PRAGMA user_version", -1, &v, NULL);
        check(sqlite3_step(v) == SQLITE_ROW && sqlite3_column_int(v, 0) == 3, "user_version untouched");
        sqlite3_finalize(v);
        sqlite3_close(raw);
        MeshMessage *old = [store messagesForChat:peer].firstObject;
        check([old.content isEqualToString:@"Alte Nachricht"] && !old.sender && [store isAccepted:peer], "old data readable and unchanged");
        check([store chatList].count == 1 && [store newestReceivedTime] == 1000, "chat list as before");

        // Erneutes Öffnen ist harmlos
        MeshStore *again = [MeshStore new];
        check([again openAtPath:path], "second open ok");
        [again setDataKey:key];
        check([((MeshMessage *)[again messagesForChat:peer].firstObject).content isEqualToString:@"Alte Nachricht"], "still readable");

        // Gruppen-Speicher
        NSString *gid = @"0123456789abcdef", *chat = MeshGroupChat(gid);
        check([again saveGroup:gid state:@"{\"v\":1}" status:MeshGroupInvited inviter:peer], "save group");
        MeshGroupStatus st = -1; NSString *inv = nil;
        check([[again groupState:gid status:&st inviter:&inv] isEqualToString:@"{\"v\":1}"] && st == MeshGroupInvited && [inv isEqualToString:peer], "load group");
        check([again saveGroup:gid state:@"{\"v\":1,\"r\":2}" status:MeshGroupMember inviter:nil] && [again groupIds].count == 1, "update keeps one row");
        MeshMessage *gm = [[MeshMessage alloc] init];
        gm.ts = 2000; gm.eventId = A64('f'); gm.cmid = @"00112233aabbccdd"; gm.sender = A64('c');
        check([again insertMessage:gm chat:chat content:@"Gruppe"] > 0, "group message stored");
        MeshMessage *back = [again messagesForChat:chat].firstObject;
        check([back.sender isEqualToString:A64('c')] && [back.content isEqualToString:@"Gruppe"], "sender stored and bound");
        check([again hasMessage:@"00112233aabbccdd" chat:chat sender:A64('c')] && ![again hasMessage:@"00112233aabbccdd" chat:chat sender:A64('d')], "dup check per sender");
        check(![again deleteMessageWithKey:@"00112233aabbccdd" chat:chat sender:A64('d')] && [again messagesForChat:chat].count == 1, "other member can't delete");
        check([again newestReceivedTime] == 2000, "group messages count for sync");
        [again addInvite:peer group:gid at:100];
        check([again hasInvite:peer group:gid since:50] && ![again hasInvite:peer group:gid since:200], "invite with age");
        check([again deleteGroup:gid] && ![again groupIds].count && ![again messagesForChat:chat].count && [again isDeleted:A64('f')], "delete group with tombstones");

        // Absender in der Datei vertauscht: Inhalt öffnet nicht mehr
        MeshMessage *gm2 = [[MeshMessage alloc] init];
        gm2.ts = 3000; gm2.eventId = A64('9'); gm2.cmid = @"aa"; gm2.sender = A64('c');
        [again insertMessage:gm2 chat:chat content:@"echt"];
        sqlite3_open(path.UTF8String, &raw);
        NSString *swap = [NSString stringWithFormat:@"UPDATE messages SET sender='%@' WHERE event_id='%@'", A64('d'), A64('9')];
        sqlite3_exec(raw, swap.UTF8String, NULL, NULL, NULL);
        sqlite3_close(raw);
        check(![((MeshMessage *)[again messagesForChat:chat].firstObject).content isEqualToString:@"echt"], "swapped sender detected");

        // Team-Speicher
        check(![again teamKey] && [again setTeamKey:A64('1')] && [[again teamKey] isEqualToString:A64('1')], "team key sealed");
        sqlite3_open(path.UTF8String, &raw);
        sqlite3_stmt *k;
        sqlite3_prepare_v2(raw, "SELECT ekey FROM team", -1, &k, NULL);
        check(sqlite3_step(k) == SQLITE_ROW && ![[NSString stringWithUTF8String:(const char *)sqlite3_column_text(k, 0)] containsString:A64('1')], "team key not in plain text");
        sqlite3_finalize(k);
        sqlite3_close(raw);
        check([again setTeamValue:"muted" value:1] && [again teamValue:"muted"] == 1 && ![again setTeamValue:"ekey; DROP TABLE x" value:1], "team columns whitelisted");
        check(![again setTeamValue:"used" value:1] && ![again teamValue:"used"], "team.used no longer written or read");
        check([again queueTeamEvent:@"{}" eventId:A64('2') created:10] && [again queuedTeamEvents].count == 1 && ![again queuedEvents].count, "team queue separate from outbox");
        MeshMessage *app = [[MeshMessage alloc] init]; app.ts = 500; app.sender = MeshSenderApp;
        MeshMessage *mine = [[MeshMessage alloc] init]; mine.ts = 600; mine.fromMe = YES; mine.eventId = A64('3');
        [again insertMessage:app chat:MeshTeamChat content:@"Hallo"];
        [again insertMessage:mine chat:MeshTeamChat content:@"Frage"];
        [again moveTeamGreetingBefore:400];
        check(((MeshMessage *)[again messagesForChat:MeshTeamChat].firstObject).ts == 400, "greeting moves before older broadcasts");
        check([again deleteTeamPersonal] && [again messagesForChat:MeshTeamChat].count == 1 && ![again queuedTeamEvents].count && [again isDeleted:A64('3')], "start over keeps greeting");
        MeshMessage *bc = [[MeshMessage alloc] init]; bc.ts = 99999; bc.sender = MeshSenderAll; bc.eventId = A64('4');
        [again insertMessage:bc chat:MeshTeamChat content:@"an alle"];
        check([again newestReceivedTime] == 3000, "team chat not used for DM sync");

        // B7: Datenbank von 0.1.28 (groups ohne pic) bekommt die Spalte, vorhandene Gruppe bleibt lesbar
        NSString *p28 = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"mesh-0128-%d.sqlite", getpid()]];
        [[NSFileManager defaultManager] removeItemAtPath:p28 error:NULL];
        sqlite3_open(p28.UTF8String, &raw);
        sqlite3_exec(raw, kSchema0126, NULL, NULL, NULL);
        NSString *sealedState = [MeshSeal seal:@"{\"v\":1,\"r\":5}" key:key context:@"groups.state|0123456789abcdef"];
        NSString *g28 = [NSString stringWithFormat:
            @"ALTER TABLE messages ADD COLUMN sender TEXT;"
             "CREATE TABLE groups(gid TEXT PRIMARY KEY, status INTEGER NOT NULL DEFAULT 0, state TEXT NOT NULL, inviter TEXT, created INTEGER NOT NULL DEFAULT 0);"
             "INSERT INTO groups(gid, status, state, created) VALUES('0123456789abcdef', 2, '%@', 77);", sealedState];
        check(sqlite3_exec(raw, g28.UTF8String, NULL, NULL, NULL) == SQLITE_OK && !hasColumn(raw, "groups", "pic"), "0.1.28 groups table without pic");
        sqlite3_close(raw);
        MeshStore *s28 = [MeshStore new];
        check([s28 openAtPath:p28], "0.1.28 opens with new code");
        [s28 setDataKey:key];
        sqlite3_open(p28.UTF8String, &raw);
        check(hasColumn(raw, "groups", "pic"), "groups.pic added");
        sqlite3_close(raw);
        MeshGroupStatus st28 = -1;
        check([[s28 groupState:gid status:&st28 inviter:NULL] isEqualToString:@"{\"v\":1,\"r\":5}"] && st28 == MeshGroupMember
              && [s28 groupCreated:gid] == 77 && ![s28 groupPicture:gid], "old group readable, no picture");
        check([s28 setGroupPicture:@"/9j/AAAA" gid:gid] && [[s28 groupPicture:gid] isEqualToString:@"/9j/AAAA"], "picture stored");
        check(![s28 setGroupPicture:@"/9j/AAAA" gid:@"fedcba9876543210"], "picture only for known groups");
        sqlite3_open(p28.UTF8String, &raw);
        sqlite3_stmt *pk;
        sqlite3_prepare_v2(raw, "SELECT pic FROM groups", -1, &pk, NULL);
        check(sqlite3_step(pk) == SQLITE_ROW && ![[NSString stringWithUTF8String:(const char *)sqlite3_column_text(pk, 0)] containsString:@"/9j/AAAA"], "picture sealed");
        sqlite3_finalize(pk);
        // An die gid gebunden: in eine andere Gruppe kopiert, öffnet es nicht
        sqlite3_exec(raw, "INSERT INTO groups(gid, status, state, pic) SELECT 'fedcba9876543210', status, state, pic FROM groups", NULL, NULL, NULL);
        sqlite3_close(raw);
        check(![s28 groupPicture:@"fedcba9876543210"], "picture bound to its gid");
        check([s28 saveGroup:gid state:@"{\"v\":1,\"r\":6}" status:MeshGroupMember inviter:nil] && [[s28 groupPicture:gid] isEqualToString:@"/9j/AAAA"], "state update keeps picture");
        check([s28 setGroupPicture:nil gid:gid] && ![s28 groupPicture:gid], "picture removed");
        [s28 setGroupPicture:@"/9j/BBBB" gid:gid];
        check([s28 deleteGroup:gid] && ![s28 groupPicture:gid], "deleting the group deletes its picture");
        [[NSFileManager defaultManager] removeItemAtPath:p28 error:NULL];

        // 0.1.30: Datenbank von 0.1.29 (Absender, Einladende, Eingeladene im Klartext, team.used gesetzt)
        NSString *p29 = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"mesh-0129-%d.sqlite", getpid()]];
        [[NSFileManager defaultManager] removeItemAtPath:p29 error:NULL];
        sqlite3_open(p29.UTF8String, &raw);
        sqlite3_exec(raw, kSchema0126, NULL, NULL, NULL);
        NSString *g29 = @"1111222233334444", *c29 = MeshGroupChat(g29), *mem = A64('c'), *invitee = A64('d'), *adm = A64('a');
        NSString *msgSealed = [MeshSeal seal:@"Hallo Gruppe" key:key context:[NSString stringWithFormat:@"messages.content|%@|0|0|0|%@|%@", c29, A64('e'), mem]];
        NSString *teamSealed = [MeshSeal seal:@"Frage" key:key context:[NSString stringWithFormat:@"messages.content|team|0|0|1|%@", A64('f')]];
        NSString *stateSealed = [MeshSeal seal:@"{\"v\":1,\"r\":3}" key:key context:[@"groups.state|" stringByAppendingString:g29]];
        NSString *invSealed = [MeshSeal seal:@"{\"v\":1,\"r\":1}" key:key context:@"groups.state|5555666677778888"];
        NSString *s29 = [NSString stringWithFormat:
            @"ALTER TABLE messages ADD COLUMN sender TEXT;"
             "CREATE TABLE groups(gid TEXT PRIMARY KEY, status INTEGER NOT NULL DEFAULT 0, state TEXT NOT NULL, inviter TEXT, created INTEGER NOT NULL DEFAULT 0, pic TEXT);"
             "CREATE TABLE group_invites(gid TEXT NOT NULL, pubkey TEXT NOT NULL, at INTEGER NOT NULL, PRIMARY KEY(gid, pubkey));"
             "CREATE TABLE team(id INTEGER PRIMARY KEY CHECK(id=1), ekey TEXT, used INTEGER NOT NULL DEFAULT 0, since INTEGER NOT NULL DEFAULT 0,"
             "  started INTEGER NOT NULL DEFAULT 0, hidden INTEGER NOT NULL DEFAULT 0, muted INTEGER NOT NULL DEFAULT 0);"
             "CREATE TABLE team_outbox(event_id TEXT PRIMARY KEY, event TEXT NOT NULL, created INTEGER NOT NULL);"
             "INSERT INTO groups(gid, status, state, inviter, created) VALUES('%@', 2, '%@', NULL, 10);"
             "INSERT INTO groups(gid, status, state, inviter, created) VALUES('5555666677778888', 0, '%@', '%@', 11);"
             "INSERT INTO group_invites(gid, pubkey, at) VALUES('%@', '%@', %lld);"
             "INSERT INTO group_invites(gid, pubkey, at) VALUES('%@', '%@', 5);"
             "INSERT INTO messages(chat, from_me, content, ts, event_id, status, kind, cmid, sender) VALUES('%@', 0, '%@', 2000, '%@', 1, 0, '0011223344556677', '%@');"
             "INSERT INTO messages(chat, from_me, content, ts, event_id, status, kind) VALUES('team', 1, '%@', 2100, '%@', 0, 0);"
             "INSERT INTO team_outbox(event_id, event, created) VALUES('%@', 'x', 2100);"
             "INSERT INTO team(id, used, started) VALUES(1, 1, 99);",
            g29, stateSealed, invSealed, adm, g29, invitee, MeshNow(), g29, A64('9'), c29, msgSealed, A64('e'), mem, teamSealed, A64('f'), A64('f')];
        check(sqlite3_exec(raw, s29.UTF8String, NULL, NULL, NULL) == SQLITE_OK, "0.1.29 database with plaintext metadata");
        sqlite3_close(raw);
        MeshStore *s29s = [MeshStore new];
        check([s29s openAtPath:p29], "0.1.29 opens with 0.1.30");
        sqlite3_open(p29.UTF8String, &raw);
        check(hasColumn(raw, "fanout", "message_rowid") && hasColumn(raw, "held_invites", "data"), "fanout and held_invites added (additive)");
        sqlite3_close(raw);
        [s29s setDataKey:key];
        sqlite3_open(p29.UTF8String, &raw);
        sqlite3_stmt *q;
        sqlite3_prepare_v2(raw, "SELECT (SELECT COUNT(*) FROM messages WHERE sender LIKE 'enc2:%'), (SELECT COUNT(*) FROM groups WHERE inviter LIKE 'enc2:%'),"
                                "(SELECT COUNT(*) FROM group_invites WHERE pubkey LIKE 'enc2:%'), (SELECT used FROM team),"
                                "(SELECT COUNT(*) FROM messages WHERE instr(sender, ?1) > 0), (SELECT COUNT(*) FROM groups WHERE instr(inviter, ?2) > 0)", -1, &q, NULL);
        sqlite3_bind_text(q, 1, mem.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(q, 2, adm.UTF8String, -1, SQLITE_TRANSIENT);
        check(sqlite3_step(q) == SQLITE_ROW && sqlite3_column_int(q, 0) == 1 && sqlite3_column_int(q, 1) == 1 && sqlite3_column_int(q, 2) == 2
              && sqlite3_column_int(q, 3) == 0 && sqlite3_column_int(q, 4) == 0 && sqlite3_column_int(q, 5) == 0, "sender, inviter, invitees sealed; team.used cleared");
        sqlite3_finalize(q);
        sqlite3_close(raw);
        MeshMessage *gm29 = [s29s messagesForChat:c29].firstObject;
        check([gm29.sender isEqualToString:mem] && [gm29.content isEqualToString:@"Hallo Gruppe"], "migrated group message readable, sender intact");
        check([s29s hasMessage:@"0011223344556677" chat:c29 sender:mem] && ![s29s hasMessage:@"0011223344556677" chat:c29 sender:adm], "dup check works on sealed sender");
        NSString *invBy = nil; MeshGroupStatus st29 = -1;
        check([s29s groupState:@"5555666677778888" status:&st29 inviter:&invBy] && [invBy isEqualToString:adm] && [s29s invitationCountFrom:adm] == 1
              && [s29s invitationCountFrom:invitee] == 0, "migrated inviter readable and countable");
        check([s29s hasInvite:invitee group:g29 since:MeshNow() - 60] && [[s29s invitesForGroup:g29 since:0] count] == 2, "migrated invitees readable");
        [s29s pruneInvitesBefore:100];
        check([[s29s invitesForGroup:g29 since:0] isEqual:@[invitee]], "prune keeps the fresh invite");
        [s29s addInvite:invitee group:g29 at:MeshNow()];
        check([[s29s invitesForGroup:g29 since:0] count] == 1, "re-adding an invitee replaces (no duplicate)");
        [s29s removeInvite:invitee group:g29];
        check(![s29s hasInvite:invitee group:g29 since:0], "invite removed");
        // Nach der Migration gilt Klartext nicht mehr (ein eingeschleuster Absender wird nicht angezeigt)
        MeshStore *again29 = [MeshStore new];
        [again29 openAtPath:p29];
        [again29 setDataKey:key];
        check([((MeshMessage *)[again29 messagesForChat:c29].firstObject).content isEqualToString:@"Hallo Gruppe"], "second open: still readable");
        sqlite3_open(p29.UTF8String, &raw);
        sqlite3_exec(raw, [[NSString stringWithFormat:@"UPDATE messages SET sender='%@' WHERE chat='%@'", mem, c29] UTF8String], NULL, NULL, NULL);
        sqlite3_close(raw);
        MeshMessage *forged29 = [again29 messagesForChat:c29].firstObject;
        check(!forged29.sender && ![forged29.content isEqualToString:@"Hallo Gruppe"], "plaintext sender after migration rejected");

        // Team-Chat: Löschen/Leeren einer noch nicht gesendeten anonymen Nachricht nimmt sie aus team_outbox
        sqlite3_open(p29.UTF8String, &raw);
        sqlite3_stmt *tq;
        sqlite3_prepare_v2(raw, "SELECT COUNT(*) FROM team_outbox", -1, &tq, NULL);
        check(sqlite3_step(tq) == SQLITE_ROW && sqlite3_column_int(tq, 0) == 1, "0.1.29 team outbox kept");
        sqlite3_finalize(tq);
        sqlite3_close(raw);
        MeshMessage *teamMsg = [again29 messagesForChat:MeshTeamChat].firstObject;
        [again29 deleteMessage:teamMsg.rowId];
        sqlite3_open(p29.UTF8String, &raw);
        sqlite3_prepare_v2(raw, "SELECT COUNT(*) FROM team_outbox", -1, &tq, NULL);
        check(sqlite3_step(tq) == SQLITE_ROW && sqlite3_column_int(tq, 0) == 0, "deleting an unsent anonymous message empties team_outbox");
        sqlite3_finalize(tq);
        sqlite3_close(raw);
        MeshMessage *t2 = [[MeshMessage alloc] init]; t2.fromMe = YES; t2.ts = 3000; t2.eventId = A64('8');
        [again29 insertMessage:t2 chat:MeshTeamChat content:@"zweite"];
        [again29 queueTeamEvent:@"{}" eventId:A64('8') created:3000];
        [again29 clearChat:MeshTeamChat at:MeshNow()];
        check(![again29 queuedTeamEvents].count, "clearing the team chat empties team_outbox");
        MeshMessage *t3 = [[MeshMessage alloc] init]; t3.fromMe = YES; t3.ts = MeshNow(); t3.eventId = A64('7'); t3.expiresAt = 10;
        [again29 insertMessage:t3 chat:MeshTeamChat content:@"dritte"];
        [again29 queueTeamEvent:@"{}" eventId:A64('7') created:3001];
        [again29 deleteExpiredAt:MeshNow()];
        check(![again29 queuedTeamEvents].count, "deleteMessagesWhere (expiry path) empties team_outbox");

        // Warteschlange nach Bytes begrenzt (je Verbindung höchstens 4 MB, mindestens eins), ohne Ausgeschlossene
        NSString *big = [@"" stringByPaddingToLength:1500 * 1024 withString:@"x" startingAtIndex:0];
        for (int i = 0; i < 5; i++) [again29 queueEvent:big eventId:[NSString stringWithFormat:@"big%d", i] created:4000 + i];
        check([again29 queuedEvents].count == 2, "outbox read limited by bytes (2 × 2 MB sealed < 4 MB < 3 ×)");
        check([again29 queuedEventsExcluding:[NSSet setWithObjects:@"big0", @"big1", nil] maxBytes:MeshOutboxMaxBytes].count == 2, "excluded events skipped before unsealing");
        check([again29 queuedEventsExcluding:nil maxBytes:10].count == 1, "at least one event even if larger than the limit");
        [[NSFileManager defaultManager] removeItemAtPath:p29 error:NULL];

        // 0.1.33: Datenbank von 0.1.32 (ohne groups.lkey/link_at und group_records) bekommt beides, alles bleibt lesbar
        NSString *p32 = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"mesh-0132-%d.sqlite", getpid()]];
        [[NSFileManager defaultManager] removeItemAtPath:p32 error:NULL];
        MeshStore *s32 = [MeshStore new];
        [s32 openAtPath:p32]; [s32 setDataKey:key];
        NSString *gstate = [NSString stringWithFormat:@"{\"v\":1,\"g\":\"0123456789abcdef\",\"n\":\"Alt\",\"a\":\"%@\",\"r\":3,\"m\":[\"%@\"],\"nm\":{},\"t\":0,\"tm\":\"read\"}", A64('a'), A64('a')];
        [s32 saveGroup:@"0123456789abcdef" state:gstate status:MeshGroupMember inviter:nil];
        [s32 addInvite:A64('c') group:@"0123456789abcdef" at:MeshNow()];
        sqlite3_open(p32.UTF8String, &raw);
        BOOL dropped = sqlite3_exec(raw, "DROP INDEX idx_group_records; DROP TABLE group_records; ALTER TABLE groups DROP COLUMN lkey;"
                                         "ALTER TABLE groups DROP COLUMN link_at;", NULL, NULL, NULL) == SQLITE_OK;
        check(dropped && !hasColumn(raw, "groups", "lkey"), "0.1.32 schema rebuilt");
        sqlite3_close(raw);
        MeshStore *s33 = [MeshStore new];
        check([s33 openAtPath:p32], "0.1.32 opens with 0.1.33");
        [s33 setDataKey:key];
        sqlite3_open(p32.UTF8String, &raw);
        check(hasColumn(raw, "groups", "lkey") && hasColumn(raw, "groups", "link_at") && hasColumn(raw, "group_records", "data"), "0.1.33 columns and table added");
        sqlite3_close(raw);
        MeshGroupStatus st32 = MeshGroupInvited;
        check([[s33 groupState:@"0123456789abcdef" status:&st32 inviter:NULL] isEqualToString:gstate] && st32 == MeshGroupMember
              && [s33 hasInvite:A64('c') group:@"0123456789abcdef" since:0], "0.1.32 group, status and invites unchanged");
        check(![s33 groupLinkKey:@"0123456789abcdef"] && ![s33 groupLinkAt:@"0123456789abcdef"], "old groups: no link key, no link join");
        check([s33 setGroupLinkKey:@"00112233445566778899aabbccddeeff" gid:@"0123456789abcdef"]
              && [[s33 groupLinkKey:@"0123456789abcdef"] isEqualToString:@"00112233445566778899aabbccddeeff"], "link key round trip");
        check([s33 addGroupRecord:MeshGroupRecordProposal gid:@"0123456789abcdef" data:@"{\"n\":\"Carol\"}" at:MeshNow()]
              && [[[s33 groupRecords:MeshGroupRecordProposal gid:@"0123456789abcdef"].firstObject objectAtIndex:2] isEqualToString:@"{\"n\":\"Carol\"}"], "group record round trip");
        sqlite3_open(p32.UTF8String, &raw);
        sqlite3_stmt *sq;
        sqlite3_prepare_v2(raw, "SELECT COUNT(*) FROM groups WHERE instr(lkey, '0011223344') > 0 OR substr(lkey,1,5) != 'enc2:' "
                                "UNION ALL SELECT COUNT(*) FROM group_records WHERE instr(data, 'Carol') > 0 OR substr(data,1,5) != 'enc2:'", -1, &sq, NULL);
        BOOL sealedOk = sqlite3_step(sq) == SQLITE_ROW && sqlite3_column_int(sq, 0) == 0 && sqlite3_step(sq) == SQLITE_ROW && sqlite3_column_int(sq, 0) == 0;
        sqlite3_finalize(sq);
        sqlite3_close(raw);
        check(sealedOk, "link key and records sealed");
        [s33 deleteGroup:@"0123456789abcdef"];
        check(![s33 groupRecords:MeshGroupRecordProposal gid:@"0123456789abcdef"].count, "deleting the group removes its records");
        [[NSFileManager defaultManager] removeItemAtPath:p32 error:NULL];
    }
    return testsDone();
}
