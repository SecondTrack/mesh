// MeshStore auf einer temporären Datei: Nachrichten, Medien-Platzhalter,
// Chatliste, Vault, Zustellstatus, Löschen.
#import "MeshTest.h"
#import "MeshStore.h"
#import "MeshStoreTesting.h"
#import "MeshStore+Vault.h"
#import "MeshStore+Outbox.h"
#import "MeshStore+Chat.h"
#import "MeshVaultRecord.h"
#import "MeshMessage.h"
#import "MeshChat.h"
#import "MeshPayload.h"
#import "MeshProfile.h"
#import "MeshSeal.h"
#import <sqlite3.h>

int main(void) { @autoreleasepool {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"mesh-store-test-%d.sqlite", getpid()]];
    MeshStore *s = [[MeshStore alloc] init];
    check([s openAtPath:path], "open");
    NSMutableData *key = [NSMutableData dataWithLength:32]; arc4random_buf(key.mutableBytes, 32);
    [s setDataKey:key];

    NSString *alice = [@"" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0];
    NSString *bob   = [@"" stringByPaddingToLength:64 withString:@"b" startingAtIndex:0];
    NSMutableData *jpeg = [NSMutableData dataWithLength:120000];
    arc4random_buf(jpeg.mutableBytes, jpeg.length);
    NSString *img = [MeshPayload contentWithImage:jpeg];

    [s insertMessageChat:alice fromMe:NO  content:@"hallo" ts:100 eventId:@"e1"];
    [s insertMessageChat:alice fromMe:YES content:img      ts:200 eventId:@"e2"];
    [s insertMessageChat:alice fromMe:NO  content:[MeshPayload contentWithVoice:jpeg seconds:9] ts:300 eventId:@"e3"];
    [s insertMessageChat:bob   fromMe:NO  content:@"MESH:IMG:kein Bild" ts:150 eventId:@"e4"];

    NSArray *ms = [s messagesForChat:alice];
    check(ms.count == 3, "three messages");
    MeshMessage *t = ms[0], *i = ms[1], *v = ms[2];
    check([t.content isEqualToString:@"hallo"], "text loaded fully");
    check([i.content isEqualToString:@"mesh:img"], "image is stub");
    check([MeshPayload kindOf:i.content] == MeshPayloadImage, "stub keeps kind");
    check([MeshPayload parse:v.content].seconds == 9, "voice stub keeps seconds");
    check([[[MeshPayload parse:[s contentOfMessage:i.rowId]] data] isEqual:jpeg], "full image on demand");
    check([[s messagesForChat:bob][0] content].length > 9, "uppercase marker is plain text");

    NSArray *chats = [s chatList];
    check(chats.count == 2, "two chats");
    MeshChat *c0 = chats[0];
    check([c0.pubkey isEqualToString:alice] && c0.ts == 300 && !c0.fromMe, "newest chat first");
    check(c0.lastContent.length <= 24 && [MeshPayload kindOf:c0.lastContent] == MeshPayloadVoice, "chat preview is stub");

    check([s hasEventId:@"e1"] && ![s hasEventId:@"nope"], "hasEventId");
    check([s markDelivered:@"e2"] && ![s markDelivered:@"e2"], "markDelivered changes once");

    // Warteschlange: unbestätigt erneut senden, bestätigt raus, nach Frist fehlgeschlagen
    [s insertMessageChat:bob fromMe:YES content:@"offline 1" ts:10 eventId:@"q1"];
    [s insertMessageChat:bob fromMe:YES content:@"offline 2" ts:11 eventId:@"q2"];
    check([s queueEvent:@"{\"id\":\"q1\"}" eventId:@"q1" created:1000]
          && [s queueEvent:@"{\"id\":\"q2\"}" eventId:@"q2" created:2000], "events queued");
    check([[s queuedEvents] isEqual:@[@"{\"id\":\"q1\"}", @"{\"id\":\"q2\"}"]], "queued events readable");
    [s markDelivered:@"q2"];
    check([s queuedEvents].count == 1, "delivered event leaves the queue");
    check([s expireQueuedBefore:1500] && [s queuedEvents].count == 0, "old event expires");
    MeshMessage *failed = nil;
    for (MeshMessage *m in [s messagesForChat:bob]) if ([m.eventId isEqualToString:@"q1"]) failed = m;
    check(failed.status == MeshMessageFailed, "expired message marked failed");
    [s deleteMessage:[s messageWithKey:@"e1" chat:alice].rowId];
    check([s messagesForChat:alice].count == 2 && [s isDeleted:@"e1"], "delete + tombstone");

    // Kontakte: Fremde sind nicht angenommen, Annehmen ist endgültig, Upsert verliert nichts
    NSString *carol = [@"" stringByPaddingToLength:64 withString:@"c" startingAtIndex:0];
    [s upsertContact:carol name:@"" accepted:NO];
    check([s isContact:carol] && ![s isAccepted:carol], "stranger not accepted");
    [s setVerified:carol verified:YES];
    check([s setContactProfile:carol pname:@"Carol" pic:@"data:image/png;base64,AAAA" createdAt:100], "profile stored");
    check(![s setContactProfile:carol pname:@"Altes Profil" pic:@"" createdAt:50], "older profile rejected");
    check(![s setContactProfile:carol pname:@"Gleich alt" pic:@"" createdAt:100], "replayed profile rejected");
    [s upsertContact:carol name:@"Caro Klartextname" accepted:NO];
    check([s isVerified:carol] && [[s picForContact:carol] length] > 0 && [[s nameForContact:carol] isEqualToString:@"Caro Klartextname"], "re-add keeps verification and profile");
    [s setAccepted:carol];
    [s upsertContact:carol name:@"" accepted:NO];
    check([s isAccepted:carol] && [[s nameForContact:carol] isEqualToString:@"Caro Klartextname"], "accept is sticky, empty name keeps old");
    check(![s isAccepted:@"unbekannt"], "unknown key not accepted");
    check([[s acceptedContactPubkeys] containsObject:carol], "accepted list");
    long long bytes = 0;
    check([s receivedCount:alice bytes:&bytes] == 1 && bytes > 100000, "received count and size (e1 deleted, only voice left)");
    int before = [s unacceptedContactCount];
    [s upsertContact:[@"" stringByPaddingToLength:64 withString:@"d" startingAtIndex:0] name:@"" accepted:NO];
    check([s unacceptedContactCount] == before + 1, "unaccepted counted");

    NSData *salt = [NSData dataWithBytes:"0123456789abcdef" length:16];
    check(![s hasVault], "no vault");
    MeshVaultRecord *rec = [MeshVaultRecord new];
    rec.salt = salt; rec.iv = salt; rec.ciphertext = jpeg; rec.pubkey = alice; rec.iterations = 7; rec.boundToDevice = YES;
    check([s saveVault:rec], "vault write");
    check([rec isEqualToRecord:[s loadVault]], "vault read");

    // Verschlüsselung: Klartext steht nirgends in der Datei
    [s insertMessageChat:bob fromMe:YES content:@"streng geheime Notiz" ts:400 eventId:@"e9"];
    MeshProfile *prof = [[MeshProfile alloc] init]; prof.name = @"Test Profil"; prof.about = @"über mich"; prof.picture = @"";
    [s saveProfile:prof];
    NSData *file = [NSData dataWithContentsOfFile:path];
    NSData *(^utf8)(NSString *) = ^(NSString *x) { return [x dataUsingEncoding:NSUTF8StringEncoding]; };
    check([file rangeOfData:utf8(@"streng geheime") options:0 range:NSMakeRange(0, file.length)].location == NSNotFound, "message not in file");
    check([file rangeOfData:utf8(@"Test Profil") options:0 range:NSMakeRange(0, file.length)].location == NSNotFound, "profile not in file");
    check([file rangeOfData:utf8(@"Caro Klartextname") options:0 range:NSMakeRange(0, file.length)].location == NSNotFound, "contact name not in file");

    // Gesperrt (kein Schlüssel): nichts lesbar, nichts schreibbar
    [s setDataKey:nil];
    check(![s insertMessageChat:bob fromMe:YES content:@"x" ts:500 eventId:@"e10"], "no write when locked");
    check(![[s messagesForChat:bob].lastObject content].length, "no read when locked");
    check([s nameForContact:carol] == nil && [s loadProfile].name.length == 0, "names hidden when locked");
    // Falscher Schlüssel liest nichts
    NSMutableData *wrong = [NSMutableData dataWithLength:32]; arc4random_buf(wrong.mutableBytes, 32);
    [s setDataKey:wrong];
    check([s nameForContact:carol] == nil, "wrong key reads nothing");
    [s setDataKey:key];
    check([[[s messagesForChat:bob].lastObject content] isEqualToString:@"streng geheime Notiz"], "readable again with key");

    // Manipulation mit Schreibzugriff auf die Datei
    sqlite3 *w; sqlite3_open(path.UTF8String, &w);
    sqlite3_exec(w, "UPDATE messages SET kind=1 WHERE event_id='e9'", NULL, NULL, NULL);          // Art kippen
    sqlite3_exec(w, "UPDATE contacts SET name=(SELECT pic FROM contacts c2 WHERE c2.pubkey=contacts.pubkey) "
                    "WHERE pubkey=(SELECT pubkey FROM contacts WHERE pic LIKE 'enc2:%' LIMIT 1)", NULL, NULL, NULL);   // Felder tauschen
    sqlite3_exec(w, "INSERT INTO messages(chat, from_me, content, ts, event_id) VALUES('ff', 0, 'untergeschoben', 9, 'z1')", NULL, NULL, NULL);
    sqlite3_close(w);
    MeshStore *again = [[MeshStore alloc] init]; [again openAtPath:path]; [again setDataKey:key];
    NSString *flipped = [again contentOfMessage:[[again messagesForChat:bob].lastObject rowId]];
    check(flipped == nil, "flipped kind makes content unreadable");
    check([again nameForContact:carol] == nil || ![[again nameForContact:carol] hasPrefix:@"data:"], "swapped fields not readable");
    check([[[again messagesForChat:@"ff"].firstObject content] length] == 0, "injected plaintext not shown");

    // Altbestand aus früherer Version (Klartext) wird beim Entsperren verschlüsselt, Klartext verschwindet
    NSString *legacyPath = [path stringByAppendingString:@"-legacy"];
    sqlite3 *raw; sqlite3_open(legacyPath.UTF8String, &raw);
    MeshStore *old = [[MeshStore alloc] init]; [old openAtPath:legacyPath];
    sqlite3_exec(raw, "INSERT INTO messages(chat, from_me, content, ts, event_id) VALUES('aa', 0, 'enc1: sieht aus wie versiegelt', 0, 'x0');"
                      "INSERT INTO messages(chat, from_me, content, ts, event_id) VALUES('aa', 0, 'alter klartext', 1, 'x1');"
                      "INSERT INTO messages(chat, from_me, content, ts, event_id) VALUES('aa', 0, 'mesh:voice:4:AAAAHGZ0eXBNNEEg', 2, 'x2');"
                      "INSERT INTO contacts(pubkey, name) VALUES('aa', 'Alter Name');", NULL, NULL, NULL);
    sqlite3_close(raw);
    [old setDataKey:key];
    NSData *lf = [NSData dataWithContentsOfFile:legacyPath];
    check([lf rangeOfData:utf8(@"alter klartext") options:0 range:NSMakeRange(0, lf.length)].location == NSNotFound
          && [lf rangeOfData:utf8(@"Alter Name") options:0 range:NSMakeRange(0, lf.length)].location == NSNotFound, "legacy plaintext gone from file");
    NSArray *lm = [old messagesForChat:@"aa"];
    check(lm.count == 3 && [[lm[0] content] isEqualToString:@"enc1: sieht aus wie versiegelt"], "plaintext starting with enc1: kept");
    check([[lm[1] content] isEqualToString:@"alter klartext"] && [MeshPayload parse:[lm[2] content]].seconds == 4
          && [[[MeshPayload parse:[old contentOfMessage:[lm[2] rowId]]] data] length] == 12, "legacy rows readable");
    sqlite3 *chk; sqlite3_open(legacyPath.UTF8String, &chk); sqlite3_stmt *uv; sqlite3_prepare_v2(chk, "PRAGMA user_version", -1, &uv, NULL);
    check(sqlite3_step(uv) == SQLITE_ROW && sqlite3_column_int(uv, 0) == 3, "migration marked done"); sqlite3_finalize(uv); sqlite3_close(chk);
    check([[old nameForContact:@"aa"] isEqualToString:@"Alter Name"], "legacy contact readable");
    [[NSFileManager defaultManager] removeItemAtPath:legacyPath error:NULL];

    // Richtung umdrehen (gesendet ↔ empfangen) macht den Inhalt unlesbar
    NSString *dave = [@"" stringByPaddingToLength:64 withString:@"e" startingAtIndex:0];
    [again insertMessageChat:dave fromMe:YES content:@"von mir" ts:600 eventId:@"d1"];
    check([[(MeshMessage *)[[again messagesForChat:dave] lastObject] content] isEqualToString:@"von mir"], "readable before flip");
    sqlite3 *w2; sqlite3_open(path.UTF8String, &w2);
    sqlite3_exec(w2, "UPDATE messages SET from_me=1-from_me WHERE event_id='d1'", NULL, NULL, NULL);
    sqlite3_close(w2);
    MeshStore *dir = [[MeshStore alloc] init]; [dir openAtPath:path]; [dir setDataKey:key];
    check([[[dir messagesForChat:dave] lastObject] content].length == 0, "flipped direction unreadable");

    // Versionsnummer zurückgesetzt + Klartext eingeschleust: mit Merker aus dem Schlüsselbund kein Erfolg
    sqlite3 *w3; sqlite3_open(path.UTF8String, &w3);
    sqlite3_exec(w3, "PRAGMA user_version = 0;"
                     "INSERT INTO messages(chat, from_me, content, ts, event_id) VALUES('ee', 0, 'gefälscht', 9, 'z2')", NULL, NULL, NULL);
    sqlite3_close(w3);
    MeshStore *guarded = [[MeshStore alloc] init]; [guarded openAtPath:path]; [guarded setDataKey:key knownSealed:YES];
    check([[[guarded messagesForChat:@"ee"] firstObject] content].length == 0, "reset user_version does not admit plaintext");

    // Schema 2 (enc2 ohne Richtung/Event-ID) wird auf Schema 3 umgestellt und bleibt lesbar
    NSString *v2path = [path stringByAppendingString:@"-v2"];
    MeshStore *v2 = [[MeshStore alloc] init]; [v2 openAtPath:v2path];
    NSString *oldSealed = [MeshSeal seal:@"aus schema 2" key:key context:@"messages.content|aa|0|0"];
    sqlite3 *w4; sqlite3_open(v2path.UTF8String, &w4);
    NSString *ins = [NSString stringWithFormat:@"INSERT INTO messages(chat, from_me, content, ts, event_id) VALUES('aa', 1, '%@', 5, 'v2a'); PRAGMA user_version = 2;", oldSealed];
    sqlite3_exec(w4, ins.UTF8String, NULL, NULL, NULL); sqlite3_close(w4);
    MeshStore *v3 = [[MeshStore alloc] init]; [v3 openAtPath:v2path]; [v3 setDataKey:key];
    check([[(MeshMessage *)[[v3 messagesForChat:@"aa"] firstObject] content] isEqualToString:@"aus schema 2"] && v3.sealed, "schema 2 migrated to 3");
    [[NSFileManager defaultManager] removeItemAtPath:v2path error:NULL];

    // Fremde: ältester zuerst, Bytes zählen, Löschen samt Tombstones, Blockieren
    NSString *s1 = [@"" stringByPaddingToLength:64 withString:@"1" startingAtIndex:0];
    NSString *s2 = [@"" stringByPaddingToLength:64 withString:@"2" startingAtIndex:0];
    MeshStore *f = [[MeshStore alloc] init]; NSString *fpath = [path stringByAppendingString:@"-fremd"];
    [f openAtPath:fpath]; [f setDataKey:key];
    [f upsertContact:s1 name:@"" accepted:NO]; [f upsertContact:s2 name:@"" accepted:NO];
    [f insertMessageChat:s1 fromMe:NO content:@"spam" ts:1 eventId:@"sp1"];
    check([[f oldestUnacceptedContact] isEqualToString:s1], "oldest stranger first");
    check([f unacceptedBytes] > 0, "stranger bytes counted");
    check([f deleteContact:s1], "delete contact commits");
    check(![f isContact:s1] && [f messagesForChat:s1].count == 0 && [f isDeleted:@"sp1"], "delete contact with tombstones");
    [f blockContact:s2];
    check([f isBlocked:s2] && ![f isContact:s2], "blocked");
    [[NSFileManager defaultManager] removeItemAtPath:fpath error:NULL];

    // Zurücksetzen: alles weg, Datenbank sofort wieder nutzbar
    check([s destroyAndReopen], "destroy and reopen");
    check(![s hasVault] && [s messagesForChat:alice].count == 0 && ![s isContact:carol], "everything gone");
    [s setDataKey:key];
    check([s insertMessageChat:alice fromMe:YES content:@"neu" ts:1 eventId:@"n1"], "usable after reset");

    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    // Neueste empfangene Nachricht (Grundlage für den since-Filter): eigene zählen nicht
    NSString *p3 = [path stringByAppendingString:@"-since"];
    MeshStore *fresh = [MeshStore new];
    [fresh openAtPath:p3];
    [fresh setDataKey:key];
    check([fresh newestReceivedTime] == 0, "nothing received yet");
    [fresh insertMessageChat:alice fromMe:NO content:@"a" ts:700 eventId:@"r1"];
    [fresh insertMessageChat:alice fromMe:YES content:@"b" ts:900 eventId:@"r2"];
    check([fresh newestReceivedTime] == 700, "newest received ignores own");
    long long imgRow = [[fresh messagesForChat:alice].firstObject rowId];
    [fresh setImageWidth:640 height:480 ofMessage:imgRow];
    MeshMessage *sized = [fresh messagesForChat:alice].firstObject;
    check(sized.width == 640 && sized.height == 480, "image size remembered");
    [[NSFileManager defaultManager] removeItemAtPath:p3 error:NULL];

    // Format der Android-App: cmid, Antworten, Reaktionen, Löschen auf Anweisung, Leeren, Selbstlöschen
    NSString *p4 = [path stringByAppendingString:@"-chat"];
    MeshStore *c = [MeshStore new];
    [c openAtPath:p4];
    [c setDataKey:key];
    MeshMessage *mine = [MeshMessage new];
    mine.fromMe = YES; mine.ts = 100; mine.eventId = @"ev-mine"; mine.cmid = @"1111111111111111"; mine.timer = 60;
    check([c insertMessage:mine chat:alice content:@"meine"] > 0 && mine.rowId > 0, "insert with meta");
    MeshMessage *theirs = [MeshMessage new];
    theirs.ts = 110; theirs.eventId = @"ev-theirs"; theirs.cmid = @"2222222222222222"; theirs.replyTo = @"1111111111111111"; theirs.timer = 30;
    [c insertMessage:theirs chat:alice content:@"Antwort"];
    MeshMessage *legacy = [MeshMessage new];
    legacy.ts = 90; legacy.eventId = @"ev-old";
    [c insertMessage:legacy chat:alice content:@"ohne cmid"];

    MeshMessage *found = [c messageWithKey:@"2222222222222222" chat:alice];
    check([found.replyTo isEqualToString:@"1111111111111111"] && found.timer == 30 && [found.content isEqualToString:@"Antwort"], "reply stored");
    check([c messageWithKey:@"2222222222222222" chat:bob] == nil, "key only within chat");
    check([[c messageWithKey:@"ev-old" chat:alice].key isEqualToString:@"ev-old"], "old message keyed by event id");

    check([c setReaction:@"👍" mine:YES key:@"2222222222222222" chat:alice], "react");
    check([c setReaction:@"❤️" mine:NO key:@"1111111111111111" chat:alice], "peer reacts");
    check(![c setReaction:@"❤️" mine:NO key:@"1111111111111111" chat:bob], "reaction from other chat ignored");
    found = [c messageWithKey:@"2222222222222222" chat:alice];
    check([found.reactMine isEqualToString:@"👍"] && !found.reactPeer, "reaction read back");
    check([[c messageWithKey:@"1111111111111111" chat:alice].reactPeer isEqualToString:@"❤️"], "peer reaction read back");
    [c setReaction:@"" mine:YES key:@"2222222222222222" chat:alice];
    check(![c messageWithKey:@"2222222222222222" chat:alice].reactMine, "reaction removed");

    check(![c deletePeerMessageWithKey:@"1111111111111111" chat:alice], "peer cannot delete my message");
    check([c deletePeerMessageWithKey:@"2222222222222222" chat:alice] && [c isDeleted:@"ev-theirs"], "peer deletes own message");

    // Selbstlöschen: eigene "Ab Gesehen" startet bei Zustellung, empfangene beim Öffnen
    MeshMessage *incoming = [MeshMessage new];
    incoming.ts = 120; incoming.eventId = @"ev-in"; incoming.cmid = @"3333333333333333"; incoming.timer = 30;
    [c insertMessage:incoming chat:alice content:@"bald weg"];
    check([c nextExpiry] == 0, "no clock running yet");
    [c markDelivered:@"ev-mine"];
    long long armed = [c messageWithKey:@"1111111111111111" chat:alice].expiresAt;
    check(armed >= time(NULL) + 59 && armed <= time(NULL) + 61, "own clock starts on delivery");
    [c startTimersInChat:alice now:1000];
    check([c messageWithKey:@"3333333333333333" chat:alice].expiresAt == 1030, "incoming clock starts on open");
    check([c nextExpiry] == 1030, "next expiry");
    check([c deleteExpiredAt:1029] == 0 && [c deleteExpiredAt:1030] == 1 && [c isDeleted:@"ev-in"], "expired deleted");

    BOOL sent = NO;
    check([c timerForChat:alice fromSent:&sent] == 0 && !sent, "no timer by default");
    [c setTimer:3600 fromSent:YES chat:alice];
    check([c timerForChat:alice fromSent:&sent] == 3600 && sent, "timer stored");

    check([c clearChat:alice at:5000] && [c messagesForChat:alice].count == 0 && [c clearedAt:alice] == 5000, "chat cleared");
    check([c isDeleted:@"ev-old"] && [c timerForChat:alice fromSent:NULL] == 3600, "clear keeps tombstones and timer");
    [c clearChat:alice at:4000];
    check([c clearedAt:alice] == 5000, "cleared never goes back");

    MeshMessage *note = [MeshMessage new];
    note.kind = MeshPayloadNotice; note.fromMe = YES; note.ts = 6000;
    [c insertMessage:note chat:alice content:[MeshPayload noticeTimer:3600 byMe:YES]];
    MeshMessage *readNote = [c messagesForChat:alice].lastObject;
    check(readNote.kind == MeshPayloadNotice && [MeshPayload parseNotice:readNote.content].seconds == 3600, "notice row");
    check([[c chatList].firstObject lastKind] == MeshPayloadNotice, "chat list knows notice");
    [[NSFileManager defaultManager] removeItemAtPath:p4 error:NULL];

    return testsDone();
}}
