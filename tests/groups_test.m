// Gruppen und Team-Chat (docs/TEAM_GROUPS_PROTOCOL.md): Prüfvektoren B6, Zustandsregeln, Annahme
// von Gruppennachrichten, Einladen/Beitreten/Verlassen/Entfernen/Auflösen, Rundbriefe, anonymer Kanal.
// Mehrere MeshMessenger tauschen Events direkt aus (ohne Relays).
#import "MeshTest.h"
#import "MeshMessenger.h"
#import "MeshMessenger+Internal.h"   // fanoutStep, Puffer (nur Tests)
#import "MeshStore.h"
#import "MeshStore+Chat.h"
#import "MeshStore+Group.h"
#import "MeshStore+Outbox.h"
#import "MeshInboxPolicy.h"
#import "MeshKeys.h"
#import "MeshEvent.h"
#import "MeshMessage.h"
#import "MeshPayload.h"
#import "MeshEnvelope.h"
#import "MeshGroupState.h"
#import "MeshGroupLink.h"
#import "MeshMessenger+GroupsInternal.h"
#import "MeshTeamPost.h"
#import "MeshTeam.h"
#import "MeshNip44.h"
#import "MeshNip04.h"
#import "MeshHex.h"
#import "MeshJSON.h"
#import "MeshTime.h"
#import "MeshPanic.h"
#import "MeshChat.h"
#import "MeshRelayPool.h"
#import "MeshRelayFake.h"
#import "MeshBase64.h"
#import <sqlite3.h>

static NSString *A64(char c) { return [@"" stringByPaddingToLength:64 withString:[NSString stringWithFormat:@"%c", c] startingAtIndex:0]; }

@interface MemoryPanicStorage : NSObject <MeshPanicStorage>
@end
@implementation MemoryPanicStorage {
    NSMutableDictionary *_items;
}
- (NSData *)panicDataNamed:(NSString *)name { return _items[name]; }
- (BOOL)setPanicData:(NSData *)data named:(NSString *)name {
    if (!_items) _items = [NSMutableDictionary dictionary];
    if (data) _items[name] = data; else [_items removeObjectForKey:name];
    return YES;
}
@end

@interface Device : NSObject <MeshMessengerDelegate, MeshTeamDelegate>
@property (nonatomic) MeshStore *store;
@property (nonatomic) MeshMessenger *messenger;
@property (nonatomic) MeshKeys *keys;
@property (nonatomic) NSMutableArray *outbox;
@property (nonatomic) MeshPanic *panic;
@property (nonatomic) int wipes, received;
@property (nonatomic, readonly) NSString *pubkey;
@property (nonatomic, copy) NSString *path;
@end

@implementation Device
- (instancetype)initNamed:(NSString *)name {
    return [self initNamed:name keys:[MeshKeys generate]];
}
- (instancetype)initNamed:(NSString *)name keys:(MeshKeys *)keys {
    if ((self = [super init])) {
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"mesh-groups-%@-%d.sqlite", name, getpid()]];
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        [[NSFileManager defaultManager] removeItemAtPath:[path stringByAppendingString:@"-journal"] error:NULL];
        _path = path;
        _store = [MeshStore new];
        [_store openAtPath:path];
        NSMutableData *key = [NSMutableData dataWithLength:32]; arc4random_buf(key.mutableBytes, 32);
        [_store setDataKey:key];
        _keys = keys;
        _panic = [[MeshPanic alloc] initWithStorage:[MemoryPanicStorage new]];
        _messenger = [[MeshMessenger alloc] initWithStore:_store keys:_keys inbox:[[MeshInboxPolicy alloc] initWithStore:_store] panic:_panic];
        _messenger.delegate = self;
        _outbox = [NSMutableArray array];
    }
    return self;
}
- (NSString *)pubkey { return [MeshHex encode:_keys.xonlyPub]; }
// Wie MeshSession: in die (versiegelte) Warteschlange und "an die Relays" (hier _outbox).
- (void)messenger:(MeshMessenger *)m send:(MeshEvent *)event {
    NSData *j = [MeshJSON dataWithObject:[event toJSONObject]];
    [_store queueEvent:[[NSString alloc] initWithData:j encoding:NSUTF8StringEncoding] eventId:event.eventId created:MeshNow()];
    [_outbox addObject:event];
}
- (void)messenger:(MeshMessenger *)m acceptedContact:(NSString *)peer {}
- (void)messengerReceivedPanic:(MeshMessenger *)m { _wipes++; }
- (void)messenger:(MeshMessenger *)m received:(MeshMessage *)message from:(NSString *)peer { _received++; }
- (void)teamChanged:(MeshTeam *)team {}
- (void)team:(MeshTeam *)team received:(MeshMessage *)message { _received++; }
// Alles Gesendete an alle zustellen, deren p-Tag passt (vorher alle Fan-out-Kopien bauen).
- (int)deliverTo:(NSArray *)others {
    [_messenger finishPendingSends];
    int changed = 0;
    for (MeshEvent *e in _outbox)
        for (Device *d in others) if ([e hasTag:@"p" value:d.pubkey]) changed += [d.messenger receive:e] ? 1 : 0;
    [_outbox removeAllObjects];
    return changed;
}
- (void)befriend:(Device *)other { [_store upsertContact:other.pubkey name:@"" accepted:YES]; }
@end

static MeshGroupState *stateFrom(NSString *json) {
    return [MeshGroupState stateFromObject:[MeshJSON objectWithData:[json dataUsingEncoding:NSUTF8StringEncoding]]];
}

#pragma mark - B6 Prüfvektoren

static void testVectors(void) {
    NSString *a = A64('a'), *b = A64('b');
    NSString *vector = [NSString stringWithFormat:@"{\"v\":1,\"g\":\"0123456789abcdef\",\"n\":\"Test\",\"a\":\"%@\",\"r\":2,\"m\":[\"%@\",\"%@\"],"
                        "\"nm\":{\"%@\":\"Anna\",\"%@\":\"Ben\"},\"t\":0,\"tm\":\"read\"}", a, a, b, a, b];
    MeshGroupState *s = stateFrom(vector);
    check(s && [s.gid isEqualToString:@"0123456789abcdef"] && s.revision == 2 && s.members.count == 2, "B6 state parses");
    check([[s nameOf:a] isEqualToString:@"Anna"] && [[s nameOf:b] isEqualToString:@"Ben"] && s.timer == 0 && !s.timerFromSent, "B6 names and timer");
    check([[s json] isEqualToString:vector], "B6 state JSON exactly");
    // Erzeugt statt gelesen: gleicher Text
    MeshGroupState *made = [[MeshGroupState stateWithGroup:@"0123456789abcdef" name:@"Test" admin:a adminName:@"Anna"] withMember:b name:@"Ben"];
    check([[made json] isEqualToString:vector], "B6 state JSON built (r 1 -> 2)");

    MeshEnvelope *e = [MeshEnvelope parse:@"\1mesh:g:0123456789abcdef\n\1mesh:x:00112233aabbccdd\nHallo"];
    check(e.type == MeshEnvelopeMessage && [e.group isEqualToString:@"0123456789abcdef"] && [e.cmid isEqualToString:@"00112233aabbccdd"]
          && [e.content isEqualToString:@"Hallo"], "B6 group text");
    e = [MeshEnvelope parse:@"\1mesh:gj:0123456789abcdef|QmVu"];
    check(e.type == MeshEnvelopeGroupJoin && [e.group isEqualToString:@"0123456789abcdef"] && [e.joinName isEqualToString:@"Ben"], "B6 join");
    check([[MeshEnvelope groupJoin:@"0123456789abcdef" name:@"Ben"] isEqualToString:@"\1mesh:gj:0123456789abcdef|QmVu"], "B6 join built");
    MeshTeamPost *p = [MeshTeamPost postFromObject:[MeshJSON objectWithData:[@"{\"v\":1,\"de\":\"Hallo\",\"en\":\"Hi\"}" dataUsingEncoding:NSUTF8StringEncoding]]];
    check([[p textPreferringGerman:YES] isEqualToString:@"Hallo"] && [[p textPreferringGerman:NO] isEqualToString:@"Hi"], "B6 broadcast de/en");
    e = [MeshEnvelope parse:@"\1mesh:anon:1\n\1mesh:x:00112233aabbccdd\nBug"];
    check(e.type == MeshEnvelopeMessage && e.anon && [e.cmid isEqualToString:@"00112233aabbccdd"] && [e.content isEqualToString:@"Bug"], "B6 anon");
    check([[MeshEnvelope anonMessage:@"Bug" cmid:@"00112233aabbccdd"] isEqualToString:@"\1mesh:anon:1\n\1mesh:x:00112233aabbccdd\nBug"], "B6 anon built");

    // Ungültig
    check([MeshEnvelope parse:@"\1mesh:g:0123456789abcde\n\1mesh:x:00112233aabbccdd\nHallo"].type == MeshEnvelopeIgnored, "B6 gid 15 chars");
    check([MeshEnvelope parse:@"\1mesh:gl:0123456789abcde"].type == MeshEnvelopeIgnored, "gid 15 chars (leave)");
    NSMutableArray *many = [NSMutableArray arrayWithObject:a];
    for (int i = 0; i < 20; i++) [many addObject:[NSString stringWithFormat:@"%062x%02x", 0, i]];
    NSDictionary *big = @{ @"v": @1, @"g": @"0123456789abcdef", @"n": @"Test", @"a": a, @"r": @2, @"m": many, @"t": @0, @"tm": @"read" };
    check(many.count == 21 && ![MeshGroupState stateFromObject:big], "B6 21 members rejected");
    NSMutableDictionary *o = [[MeshJSON objectWithData:[vector dataUsingEncoding:NSUTF8StringEncoding]] mutableCopy];
    o[@"n"] = @"  ​ ";
    check(![MeshGroupState stateFromObject:o], "B6 empty name rejected");
    o[@"n"] = [@"" stringByPaddingToLength:51 withString:@"x" startingAtIndex:0];
    check(![MeshGroupState stateFromObject:o], "name > 50 rejected");
    o[@"n"] = @"Test"; o[@"m"] = @[a, b, b];
    check(![MeshGroupState stateFromObject:o], "duplicate members rejected");
    o[@"m"] = @[b];
    check(![MeshGroupState stateFromObject:o], "members without admin rejected");
    o[@"m"] = @[a, @"xyz"];
    check(![MeshGroupState stateFromObject:o], "bad member pk rejected");
    o[@"m"] = @[a]; o[@"r"] = @YES;
    check(![MeshGroupState stateFromObject:o], "boolean revision rejected");
    o[@"r"] = @1.5;
    check(![MeshGroupState stateFromObject:o], "fractional revision rejected");
    o[@"r"] = @2; o[@"v"] = @2;
    check(![MeshGroupState stateFromObject:o], "unknown version rejected");
    o[@"v"] = @1; o[@"t"] = @(-5);
    check(![MeshGroupState stateFromObject:o], "negative timer rejected");
    o[@"t"] = @0; o[@"nm"] = @{ a: [@"" stringByPaddingToLength:60 withString:@"n" startingAtIndex:0], A64('c'): @"Fremd" };
    MeshGroupState *trunc = [MeshGroupState stateFromObject:o];
    check(trunc && ![trunc nameOf:a].length && ![trunc nameOf:A64('c')].length, "B8.6 member name > 40 dropped, members only");
    o[@"nm"] = @{ a: [@"" stringByPaddingToLength:40 withString:@"n" startingAtIndex:0] };
    check([[MeshGroupState stateFromObject:o] nameOf:a].length == 40, "member name of 40 kept");
    o[@"nm"] = @{ a: @"An‮na\n" };
    check([[[MeshGroupState stateFromObject:o] nameOf:a] isEqualToString:@"Anna"], "invisible chars removed");
    o[@"g"] = @"0123456789ABCDEF"; o[@"a"] = a.uppercaseString; o[@"m"] = @[a.uppercaseString];
    MeshGroupState *upper = [MeshGroupState stateFromObject:o];
    check([upper.gid isEqualToString:@"0123456789abcdef"] && [upper.admin isEqualToString:a] && [upper hasMember:a], "hex lowercased");
    o[@"m"] = @[];
    check([MeshGroupState stateFromObject:o].dissolved, "m=[] means dissolved");

    // Marker-Regeln des Umschlags
    check([MeshEnvelope parse:@"\1mesh:g:0123456789abcdef\n\1mesh:clr:"].type == MeshEnvelopeIgnored, "group header only before message/reaction/delete");
    check([MeshEnvelope parse:@"\1mesh:g:0123456789abcdef\n\1mesh:g:0123456789abcdef\nHallo"].type == MeshEnvelopeIgnored, "two group headers");
    check([MeshEnvelope parse:@"\1mesh:mb:xyz\n\1mesh:gl:0123456789abcdef"].type == MeshEnvelopeIgnored, "group control with bundle ignored");
    check([MeshEnvelope parse:@"\1mesh:anon:1\n\1mesh:rx:abc|x"].type == MeshEnvelopeIgnored, "anon only before messages");
    check([MeshEnvelope parse:@"\1mesh:anon:2\nBug"].type == MeshEnvelopeIgnored, "anon value must be 1");
    NSString *huge = [@"\1mesh:gs:" stringByPaddingToLength:16 * 1024 + 20 withString:@"A" startingAtIndex:0];
    check([MeshEnvelope parse:huge].type == MeshEnvelopeIgnored, "control base64 > 16 KB rejected");
    check([MeshEnvelope parse:@"\1mesh:gs:!!!"].type == MeshEnvelopeIgnored, "control not base64 rejected");

    // Rundbrief-Inhalt
    check(![MeshTeamPost postFromObject:@{ @"v": @1, @"de": @"Hallo \1mesh:x:1" }], "B6 broadcast with marker rejected");
    check(![MeshTeamPost postFromObject:@{ @"v": @1, @"de": [@"" stringByPaddingToLength:4001 withString:@"x" startingAtIndex:0] }], "broadcast > 4000 rejected");
    check(![MeshTeamPost postFromObject:@{ @"v": @1, @"de": @"", @"en": @" " }], "broadcast empty rejected");
    check([[[MeshTeamPost postFromObject:@{ @"v": @1, @"en": @"Hi‮\tthere" }] textPreferringGerman:YES] isEqualToString:@"Hithere"], "broadcast sanitized, fallback language");
}

#pragma mark - Gruppen

static MeshMessage *lastIn(Device *d, NSString *gid) { return (MeshMessage *)[d.store messagesForChat:MeshGroupChat(gid)].lastObject; }

static MeshGroupStatus statusOf(Device *d, NSString *gid) {
    MeshGroupStatus st = -1;
    [d.messenger groupState:gid status:&st inviter:NULL];
    return st;
}

static void testGroups(void) {
    Device *anna = [[Device alloc] initNamed:@"anna"], *ben = [[Device alloc] initNamed:@"ben"], *cleo = [[Device alloc] initNamed:@"cleo"],
           *eve = [[Device alloc] initNamed:@"eve"], *dora = [[Device alloc] initNamed:@"dora"];
    NSArray *all = @[anna, ben, cleo, eve];
    [anna befriend:ben]; [anna befriend:cleo];
    [ben befriend:anna];   // Cleo hat Anna nicht angenommen

    NSString *gid = [anna.messenger createGroup:@"Familie" members:@[ben.pubkey, cleo.pubkey, eve.pubkey] myName:@"Anna"];
    check(gid.length == 16 && statusOf(anna, gid) == MeshGroupMember, "created, admin is member");
    check([anna.messenger pendingInvitesForGroup:gid].count == 2, "only accepted contacts invited");
    [anna deliverTo:all];
    check(statusOf(ben, gid) == MeshGroupInvited, "ben got invitation");
    check(![cleo.store groupIds].count, "invitation from non-accepted contact rejected");

    // Einladung von jemandem, der nicht Admin ist
    MeshGroupState *fake = [MeshGroupState stateWithGroup:@"aaaaaaaaaaaaaaaa" name:@"X" admin:anna.pubkey adminName:@""];
    MeshEvent *forged = [MeshEvent kind:4 content:[MeshNip44 encrypt:[MeshEnvelope groupInvite:[fake json]] keys:dora.keys peerXonlyPub:ben.keys.xonlyPub]
                                   tags:@[@[@"p", ben.pubkey]]];
    [forged signWithKeys:dora.keys];
    [ben befriend:dora];
    check(![ben.messenger receive:forged] && statusOf(ben, @"aaaaaaaaaaaaaaaa") == (MeshGroupStatus)-1, "invite from non-admin rejected");

    // Nachricht vor dem Beitritt: verworfen
    check([ben.messenger acceptInvite:gid myName:@"Ben"] && statusOf(ben, gid) == MeshGroupJoining, "ben joining");
    [anna.messenger sendGroup:gid content:@"zu früh" replyTo:nil];   // geht an niemanden (Ben noch nicht in m)
    NSString *early = [MeshEnvelope inGroup:gid plain:[MeshEnvelope message:@"zu früh" cmid:@"0f0f0f0f0f0f0f0f" replyTo:nil timer:0 mode:MeshTimerFromRead bundle:nil]];
    MeshEvent *ee = [MeshEvent kind:4 content:[MeshNip44 encrypt:early keys:anna.keys peerXonlyPub:ben.keys.xonlyPub] tags:@[@[@"p", ben.pubkey]]];
    [ee signWithKeys:anna.keys];
    check(![ben.messenger receive:ee] && ![ben.store messagesForChat:MeshGroupChat(gid)].count, "message while joining rejected");
    check([ben deliverTo:all] == 1 && statusOf(anna, gid) == MeshGroupMember, "anna took the join");
    MeshGroupState *s = [anna.messenger groupState:gid status:NULL inviter:NULL];
    check(s.members.count == 2 && [[s nameOf:ben.pubkey] isEqualToString:@"Ben"] && s.revision == 3, "state r+1 with ben (create 1, invite 2, join 3)");
    check([anna.messenger pendingInvitesForGroup:gid].count == 1, "invite consumed");
    [anna deliverTo:all];
    check(statusOf(ben, gid) == MeshGroupMember, "ben member after state");

    // Gleiche Einladung nochmal einlösen: nichts
    MeshEvent *join = [MeshEvent kind:4 content:[MeshNip44 encrypt:[MeshEnvelope groupJoin:gid name:@"Eve"] keys:eve.keys peerXonlyPub:anna.keys.xonlyPub]
                                 tags:@[@[@"p", anna.pubkey]]];
    [join signWithKeys:eve.keys];
    check(![anna.messenger receive:join], "join without invitation rejected");

    // Nachrichten
    MeshMessage *m = [anna.messenger sendGroup:gid content:@"Hallo zusammen" replyTo:nil];
    check(m && anna.outbox.count == 1, "fan-out to one member");
    check([anna deliverTo:all] == 1, "ben receives group text");
    MeshMessage *got = [ben.store messagesForChat:MeshGroupChat(gid)].lastObject;
    check([got.content isEqualToString:@"Hallo zusammen"] && [got.sender isEqualToString:anna.pubkey] && [got.cmid isEqualToString:m.cmid], "sender and cmid kept");
    check(![ben.store isContact:A64('0')] && [ben.store acceptedContactPubkeys].count == 2, "no contacts created");
    MeshEvent *again = nil;
    [anna.messenger sendGroup:gid content:@"zweimal" replyTo:nil];
    again = anna.outbox.firstObject;
    [anna deliverTo:all];
    check(![ben.messenger receive:again], "duplicate event ignored");

    // Nicht-Kontakt als Mitglied: Cleo (Kontakt von Anna, nicht von Ben) kommt dazu
    [cleo befriend:anna];
    [anna.messenger invite:@[cleo.pubkey] toGroup:gid];
    [anna deliverTo:all];
    check(statusOf(cleo, gid) == MeshGroupInvited, "cleo invited");
    [cleo.messenger acceptInvite:gid myName:@"Cleo"];
    [cleo deliverTo:all];
    [anna deliverTo:all];
    check(statusOf(cleo, gid) == MeshGroupMember && [[ben.messenger groupState:gid status:NULL inviter:NULL] hasMember:cleo.pubkey], "cleo member everywhere");
    NSUInteger before = [ben.store messagesForChat:MeshGroupChat(gid)].count;
    MeshMessage *cm = [cleo.messenger sendGroup:gid content:@"Hi Ben" replyTo:nil];
    for (MeshEvent *e in cleo.outbox) if ([e hasTag:@"p" value:ben.pubkey]) check([e.content rangeOfString:@"?iv="].location == NSNotFound, "non-contact: NIP-44");
    [cleo deliverTo:all];
    check(cm && [ben.store messagesForChat:MeshGroupChat(gid)].count > before && ![ben.store isContact:cleo.pubkey], "message from non-contact member, no request");
    check(![ben.store requestPubkeys:10].count, "no message request created");

    // Kein Bundle an Nicht-Kontakte: Cleo schreibt Ben -> Klartext ohne mb
    [cleo.messenger sendGroup:gid content:@"ohne bundle" replyTo:nil];
    for (MeshEvent *e in cleo.outbox) if ([e hasTag:@"p" value:ben.pubkey]) {
        NSString *txt = [MeshNip44 decrypt:e.content keys:ben.keys peerXonlyPub:cleo.keys.xonlyPub];
        check(txt && [MeshEnvelope parse:txt].bundle == nil, "no bundle for non-contact");
    }
    [cleo deliverTo:all];

    // Nicht-Mitglied schreibt in die Gruppe: verworfen
    NSString *intr = [MeshEnvelope inGroup:gid plain:[MeshEnvelope message:@"Spam" cmid:@"0011223344556677" replyTo:nil timer:0 mode:MeshTimerFromRead bundle:nil]];
    MeshEvent *spam = [MeshEvent kind:4 content:[MeshNip44 encrypt:intr keys:eve.keys peerXonlyPub:ben.keys.xonlyPub] tags:@[@[@"p", ben.pubkey]]];
    [spam signWithKeys:eve.keys];
    NSUInteger n = [ben.store messagesForChat:MeshGroupChat(gid)].count;
    check(![ben.messenger receive:spam] && [ben.store messagesForChat:MeshGroupChat(gid)].count == n && ![ben.store isContact:eve.pubkey], "non-member rejected, no request");

    // Dateien gibt es in Gruppen nicht
    NSString *file = [MeshPayload contentWithFile:[NSData dataWithBytes:"abc" length:3] name:@"a.txt" mime:@"text/plain"];
    check(![anna.messenger sendGroup:gid content:file replyTo:nil], "no files sent in groups");
    NSString *fileMsg = [MeshEnvelope inGroup:gid plain:[MeshEnvelope message:file cmid:@"1122334455667788" replyTo:nil timer:0 mode:MeshTimerFromRead bundle:nil]];
    MeshEvent *fe = [MeshEvent kind:4 content:[MeshNip44 encrypt:fileMsg keys:anna.keys peerXonlyPub:ben.keys.xonlyPub] tags:@[@[@"p", ben.pubkey]]];
    [fe signWithKeys:anna.keys];
    check(![ben.messenger receive:fe], "file in group rejected");
    // Zu große Nachricht
    NSString *bigText = [@"" stringByPaddingToLength:64 * 1024 + 1 withString:@"x" startingAtIndex:0];
    NSString *bigMsg = [MeshEnvelope inGroup:gid plain:[MeshEnvelope message:bigText cmid:@"2233445566778899" replyTo:nil timer:0 mode:MeshTimerFromRead bundle:nil]];
    MeshEvent *be = [MeshEvent kind:4 content:[MeshNip44 encrypt:@"x" keys:anna.keys peerXonlyPub:ben.keys.xonlyPub] tags:@[@[@"p", ben.pubkey]]];
    be.content = [MeshNip04 encrypt:bigMsg sharedX:[anna.keys ecdhSharedX:ben.keys.xonlyPub]];   // zu groß für NIP-44
    [be signWithKeys:anna.keys];
    check(![ben.messenger receive:be], "oversized group text rejected");

    // Panik-Codewort im Gruppentext löst nicht aus
    check([ben.panic setCodeword:@"Leuchtturm" pubkeys:@[ben.pubkey]], "codeword set");
    [anna.messenger sendGroup:gid content:@"Leuchtturm" replyTo:nil];
    [anna deliverTo:all];
    check(ben.wipes == 0 && [lastIn(ben, gid).content isEqualToString:@"Leuchtturm"], "codeword in group never wipes");

    // Reaktion und Löschen: nur eigene
    MeshMessage *annas = [anna.messenger sendGroup:gid content:@"löschbar" replyTo:nil];
    [anna deliverTo:all];
    MeshMessage *atBen = [ben.store messageWithKey:annas.cmid chat:MeshGroupChat(gid)];
    check([ben.messenger reactInGroup:gid emoji:@"👍" to:atBen], "react in group");
    [ben deliverTo:all];
    check([[anna.store messageWithKey:annas.cmid chat:MeshGroupChat(gid)].reactPeer isEqualToString:@"👍"], "reaction arrives");
    NSString *forgedDel = [MeshEnvelope inGroup:gid plain:[MeshEnvelope deletionOf:annas.cmid]];
    MeshEvent *fd = [MeshEvent kind:4 content:[MeshNip44 encrypt:forgedDel keys:cleo.keys peerXonlyPub:ben.keys.xonlyPub] tags:@[@[@"p", ben.pubkey]]];
    [fd signWithKeys:cleo.keys];
    [ben.messenger receive:fd];
    check([ben.store messageWithKey:annas.cmid chat:MeshGroupChat(gid)] != nil, "member can't delete another's message");
    check([anna.messenger deleteInGroup:gid message:annas], "delete for all");
    [anna deliverTo:all];
    check(![ben.store messageWithKey:annas.cmid chat:MeshGroupChat(gid)], "deleted at ben");

    // Zustand: nur vom Admin, nur höhere Revision
    s = [anna.messenger groupState:gid status:NULL inviter:NULL];
    MeshGroupState *stale = stateFrom([s json]);
    MeshEvent *old = [MeshEvent kind:4 content:[MeshNip44 encrypt:[MeshEnvelope groupState:[[stale renamed:@"Alt"] json]] keys:cleo.keys peerXonlyPub:ben.keys.xonlyPub]
                                 tags:@[@[@"p", ben.pubkey]]];
    [old signWithKeys:cleo.keys];
    check(![ben.messenger receive:old] && [[ben.messenger groupState:gid status:NULL inviter:NULL].name isEqualToString:@"Familie"], "state from non-admin rejected");
    MeshEvent *same = [MeshEvent kind:4 content:[MeshNip44 encrypt:[MeshEnvelope groupState:[s json]] keys:anna.keys peerXonlyPub:ben.keys.xonlyPub]
                                  tags:@[@[@"p", ben.pubkey]]];
    [same signWithKeys:anna.keys];
    check(![ben.messenger receive:same], "state with same revision rejected");

    // Umbenennen, Timer (nur Admin)
    check(![ben.messenger renameGroup:gid to:@"Ben's"], "non-admin can't rename");
    check([anna.messenger renameGroup:gid to:@"Familie Müller"], "admin renames");
    [anna deliverTo:all];
    check([[ben.messenger groupState:gid status:NULL inviter:NULL].name isEqualToString:@"Familie Müller"], "rename arrives");
    MeshPayload *note = [MeshPayload parseNotice:lastIn(ben, gid).content];
    check(note.groupNotice == MeshGroupNoticeRenamed && [note.text isEqualToString:@"Familie Müller"], "rename notice");
    check([anna.messenger setGroupTimer:3600 fromSent:YES group:gid], "admin sets timer");
    [anna deliverTo:all];
    MeshGroupState *bs = [ben.messenger groupState:gid status:NULL inviter:NULL];
    check(bs.timer == 3600 && bs.timerFromSent, "timer in state");
    MeshMessage *t = [ben.messenger sendGroup:gid content:@"weg in 1h" replyTo:nil];
    check(t.timer == 3600 && t.expiresAt > 0, "messages carry the group timer");
    [ben deliverTo:all];

    // Verlassen: Cleo geht
    check([cleo.messenger leaveGroup:gid] && statusOf(cleo, gid) == MeshGroupLeft, "cleo left");
    [cleo deliverTo:all];
    check(![[ben.messenger groupState:gid status:NULL inviter:NULL] hasMember:cleo.pubkey], "ben stops sending to cleo at once");
    check(![[anna.messenger groupState:gid status:NULL inviter:NULL] hasMember:cleo.pubkey], "admin removed cleo");
    [anna deliverTo:all];
    [ben.messenger sendGroup:gid content:@"ohne Cleo" replyTo:nil];
    BOOL toCleo = NO;
    for (MeshEvent *e in ben.outbox) toCleo |= [e hasTag:@"p" value:cleo.pubkey];
    check(!toCleo, "nothing sent to who left");
    [ben deliverTo:all];

    // Entfernen: Ben fliegt raus, sieht es, kann nicht mehr schreiben
    check([anna.messenger removeMember:ben.pubkey fromGroup:gid], "admin removes ben");
    [anna deliverTo:all];
    check(statusOf(ben, gid) == MeshGroupRemoved, "ben: no longer in group");
    check(![ben.messenger sendGroup:gid content:@"noch da?" replyTo:nil], "removed can't send");
    check([MeshPayload parseNotice:lastIn(ben, gid).content].groupNotice == MeshGroupNoticeYouRemoved, "removed notice");

    // Auflösen: Ben wieder rein (B8.1: jede Einladung r+1, also auch für früher Entfernte gültig), dann geht der Admin
    long long rBefore = [anna.messenger groupState:gid status:NULL inviter:NULL].revision;
    [anna.messenger invite:@[ben.pubkey] toGroup:gid];
    check([anna.messenger groupState:gid status:NULL inviter:NULL].revision == rBefore + 1, "B8.1 invite bumps revision");
    [anna deliverTo:all];
    check(statusOf(ben, gid) == MeshGroupInvited, "B8.1 re-invite of a removed member accepted");
    [ben.messenger acceptInvite:gid myName:@"Ben"];
    [ben deliverTo:all]; [anna deliverTo:all];
    check(statusOf(ben, gid) == MeshGroupMember, "ben back");
    check([anna.messenger leaveGroup:gid] && statusOf(anna, gid) == MeshGroupDissolved, "admin dissolves");
    [anna deliverTo:all];
    check(statusOf(ben, gid) == MeshGroupDissolved, "dissolved at ben");
    check(![ben.messenger sendGroup:gid content:@"?" replyTo:nil], "dissolved is read-only");

    // Ablehnen ist unsichtbar
    NSString *g2 = [anna.messenger createGroup:@"Zwei" members:@[ben.pubkey] myName:@"Anna"];
    [anna deliverTo:all];
    [ben.messenger declineInvite:g2];
    check(statusOf(ben, g2) == (MeshGroupStatus)-1 && !ben.outbox.count, "decline sends nothing, forgets");

    // Spam-Deckel: höchstens 5 offene Einladungen je Einladendem
    for (int i = 0; i < 7; i++) [anna.messenger createGroup:[NSString stringWithFormat:@"Spam %d", i] members:@[ben.pubkey] myName:@"Anna"];
    [anna deliverTo:all];
    int open = 0;
    for (NSString *g in [ben.store groupIds]) open += statusOf(ben, g) == MeshGroupInvited;
    check(open == 5, "at most 5 open invitations per inviter");
    // Tief verschachteltes JSON wird gar nicht erst geparst
    NSMutableString *deep = [NSMutableString string];
    for (int i = 0; i < 64; i++) [deep appendString:@"["];
    check(!MeshJSONShallow([deep dataUsingEncoding:NSUTF8StringEncoding], 4) && MeshJSONShallow([@"{\"a\":[\"[[[[[\"]}" dataUsingEncoding:NSUTF8StringEncoding], 4), "JSON depth guard");

    // Höchstens 20 Mitglieder
    MeshGroupState *full = [MeshGroupState stateWithGroup:@"0123456789abcdef" name:@"Voll" admin:anna.pubkey adminName:@""];
    for (int i = 0; i < 19; i++) full = [full withMember:[NSString stringWithFormat:@"%062x%02x", 1, i] name:@""];
    check(full.members.count == 20 && ![full withMember:A64('9') name:@""], "21st member refused");
}


#pragma mark - B7 Gruppenbild

// Kleines "JPEG": nur die Magic Bytes zählen hier (dekodiert wird erst in der Oberfläche).
static NSData *fakeJPEG(NSUInteger length, uint8_t fill) {
    NSMutableData *d = [NSMutableData dataWithLength:length];
    memset(d.mutableBytes, fill, length);
    uint8_t *b = d.mutableBytes; b[0] = 0xFF; b[1] = 0xD8; b[2] = 0xFF;
    return d;
}

static MeshEvent *dmFrom(Device *from, Device *to, NSString *plain) {
    MeshEvent *e = [MeshEvent kind:4 content:[MeshNip44 encrypt:plain keys:from.keys peerXonlyPub:to.keys.xonlyPub] tags:@[@[@"p", to.pubkey]]];
    [e signWithKeys:from.keys];
    return e;
}

static void testPictureVectors(void) {
    NSData *abc = [@"abc" dataUsingEncoding:NSUTF8StringEncoding];
    check([[MeshMessenger groupPictureHash:abc] isEqualToString:@"ba7816bf8f01cfea"], "B7 p of \"abc\"");
    MeshEnvelope *e = [MeshEnvelope parse:@"\1mesh:gp:0123456789abcdef|YWJj"];
    check(e.type == MeshEnvelopeGroupPicture && [e.group isEqualToString:@"0123456789abcdef"] && [e.groupPicture isEqualToData:abc], "B7 gp parses");
    check([[MeshEnvelope groupPicture:abc gid:@"0123456789abcdef"] isEqualToString:@"\1mesh:gp:0123456789abcdef|YWJj"], "B7 gp built");
    check([MeshEnvelope parse:@"\1mesh:gp:0123456789ABCDEF|YWJj"].group.length == 16
          && [[MeshEnvelope parse:@"\1mesh:gp:0123456789ABCDEF|YWJj"].group isEqualToString:@"0123456789abcdef"], "gp gid lowercased");
    check([MeshEnvelope parse:@"\1mesh:gp:0123456789abcdef|"].type == MeshEnvelopeIgnored, "gp without bytes ignored");
    check([MeshEnvelope parse:@"\1mesh:gp:0123456789abcde|YWJj"].type == MeshEnvelopeIgnored, "gp gid 15 chars ignored");
    check([MeshEnvelope parse:@"\1mesh:gp:0123456789abcdef|YW!j"].type == MeshEnvelopeIgnored, "gp not base64 ignored");
    check([MeshEnvelope parse:@"\1mesh:mb:xyz\n\1mesh:gp:0123456789abcdef|YWJj"].type == MeshEnvelopeIgnored, "gp with bundle ignored");
    check([MeshEnvelope parse:@"\1mesh:g:0123456789abcdef\n\1mesh:gp:0123456789abcdef|YWJj"].type == MeshEnvelopeIgnored, "gp with group header ignored");
    NSString *limit = [MeshEnvelope groupPicture:fakeJPEG(64 * 1024, 1) gid:@"0123456789abcdef"];
    NSString *over = [MeshEnvelope groupPicture:fakeJPEG(64 * 1024 + 1, 1) gid:@"0123456789abcdef"];
    check([MeshEnvelope parse:limit].groupPicture.length == 64 * 1024, "gp with 64 KB accepted by the parser");
    check([MeshEnvelope parse:over].type == MeshEnvelopeIgnored, "gp over 64 KB ignored");

    // Zustand mit p: als letztes Feld, nur wenn gesetzt; B6 ohne Bild bleibt byte-gleich
    NSString *a = A64('a'), *b = A64('b');
    NSString *b6 = [NSString stringWithFormat:@"{\"v\":1,\"g\":\"0123456789abcdef\",\"n\":\"Test\",\"a\":\"%@\",\"r\":2,\"m\":[\"%@\",\"%@\"],"
                    "\"nm\":{\"%@\":\"Anna\",\"%@\":\"Ben\"},\"t\":0,\"tm\":\"read\"}", a, a, b, a, b];
    MeshGroupState *s = stateFrom(b6);
    check(s && !s.picture && [[s json] isEqualToString:b6], "B6 without p unchanged");
    MeshGroupState *withP = [s withPicture:@"ba7816bf8f01cfea"];
    NSString *expected = [[b6 substringToIndex:b6.length - 1] stringByAppendingString:@",\"p\":\"ba7816bf8f01cfea\"}"];
    expected = [expected stringByReplacingOccurrencesOfString:@"\"r\":2" withString:@"\"r\":3"];
    check(withP.revision == 3 && [[withP json] isEqualToString:expected], "p last field, r+1");
    MeshGroupState *back = stateFrom(expected);
    check([back.picture isEqualToString:@"ba7816bf8f01cfea"] && [[back json] isEqualToString:expected], "p round trip");
    check(![withP withPicture:nil].picture && ![[[withP withPicture:nil] json] containsString:@"\"p\""], "remove: no p written");
    check([[withP renamed:@"Neu"].picture isEqualToString:@"ba7816bf8f01cfea"], "p kept on other changes");
    NSMutableDictionary *o = [[MeshJSON objectWithData:[expected dataUsingEncoding:NSUTF8StringEncoding]] mutableCopy];
    o[@"p"] = @"";
    check([MeshGroupState stateFromObject:o] && ![MeshGroupState stateFromObject:o].picture, "empty p = no picture");
    o[@"p"] = @"BA7816BF8F01CFEA";
    check([[MeshGroupState stateFromObject:o].picture isEqualToString:@"ba7816bf8f01cfea"], "p lowercased");
    o[@"p"] = @"ba7816bf8f01cfe";
    check(![MeshGroupState stateFromObject:o], "p with 15 hex rejected");
    o[@"p"] = @"ba7816bf8f01cfeg";
    check(![MeshGroupState stateFromObject:o], "p not hex rejected");
    o[@"p"] = @12;
    check(![MeshGroupState stateFromObject:o], "p not a string rejected");
    check(![s withPicture:@"xyz"], "withPicture checks the hash");
}

static void testGroupPicture(void) {
    Device *anna = [[Device alloc] initNamed:@"panna"], *ben = [[Device alloc] initNamed:@"pben"], *cleo = [[Device alloc] initNamed:@"pcleo"];
    NSArray *all = @[anna, ben, cleo];
    [anna befriend:ben]; [ben befriend:anna]; [anna befriend:cleo]; [cleo befriend:anna];
    NSString *gid = [anna.messenger createGroup:@"Bild" members:@[ben.pubkey] myName:@"Anna"];
    [anna deliverTo:all];
    [ben.messenger acceptInvite:gid myName:@"Ben"];
    [ben deliverTo:all]; [anna deliverTo:all];
    check(statusOf(ben, gid) == MeshGroupMember && ![ben.messenger groupPicture:gid], "member, no picture yet");

    // Admin setzt ein Bild: r+1, gs an alle, gp an jedes Mitglied
    NSData *pic1 = fakeJPEG(2000, 7);
    long long r0 = [anna.messenger groupState:gid status:NULL inviter:NULL].revision;
    check(![ben.messenger setGroupPicture:pic1 group:gid], "non-admin can't set the picture");
    check(!ben.outbox.count, "non-admin sends nothing");
    check([anna.messenger setGroupPicture:pic1 group:gid], "admin sets picture");
    MeshGroupState *as = [anna.messenger groupState:gid status:NULL inviter:NULL];
    check(as.revision == r0 + 1 && [as.picture isEqualToString:[MeshMessenger groupPictureHash:pic1]], "state r+1 with p");
    check(anna.outbox.count == 2 && [[anna.messenger groupPicture:gid] isEqualToString:[MeshBase64 encode:pic1]], "gs + gp to ben, admin shows it");
    [anna deliverTo:all];
    check([[ben.messenger groupPicture:gid] isEqualToString:[MeshBase64 encode:pic1]], "ben has the picture");

    // gp von einem Nicht-Admin (sogar mit passendem Hash): verworfen
    [anna.messenger invite:@[cleo.pubkey] toGroup:gid];
    [anna deliverTo:all];
    check(statusOf(cleo, gid) == MeshGroupInvited && ![cleo.messenger groupPicture:gid], "invitation shows no picture");
    [cleo.messenger acceptInvite:gid myName:@"Cleo"];
    [cleo deliverTo:all];
    BOOL gpToCleo = NO;
    for (MeshEvent *e in anna.outbox) if ([e hasTag:@"p" value:cleo.pubkey]) {
        NSString *txt = [MeshNip44 decrypt:e.content keys:cleo.keys peerXonlyPub:anna.keys.xonlyPub]
                     ?: [MeshNip04 decrypt:e.content sharedX:[cleo.keys ecdhSharedX:anna.keys.xonlyPub]];
        gpToCleo |= [MeshEnvelope parse:txt].type == MeshEnvelopeGroupPicture;
    }
    check(gpToCleo, "new member gets gp from the admin");
    [anna deliverTo:all];
    check(statusOf(cleo, gid) == MeshGroupMember && [[cleo.messenger groupPicture:gid] isEqualToString:[MeshBase64 encode:pic1]], "new member shows the picture");

    NSData *pic2 = fakeJPEG(3000, 9);
    MeshGroupState *bs = [ben.messenger groupState:gid status:NULL inviter:NULL];
    MeshEvent *fromCleo = dmFrom(cleo, ben, [MeshEnvelope groupPicture:pic1 gid:gid]);
    check(![ben.messenger receive:fromCleo] && [[ben.messenger groupPicture:gid] isEqualToString:[MeshBase64 encode:pic1]], "gp from non-admin rejected");

    // Falscher Hash (vom Admin signiert, aber nicht das Bild des Zustands): nicht angezeigt
    check(![ben.messenger receive:dmFrom(anna, ben, [MeshEnvelope groupPicture:pic2 gid:gid])]
          && [[ben.messenger groupPicture:gid] isEqualToString:[MeshBase64 encode:pic1]], "gp with hash mismatch not shown");
    check([ben.messenger groupState:gid status:NULL inviter:NULL].revision == bs.revision, "state unchanged");

    // Bild vor dem Zustand: wartet (nur RAM), wird mit dem passenden Zustand übernommen
    NSData *pic3 = fakeJPEG(4000, 3);
    check([anna.messenger setGroupPicture:pic3 group:gid], "admin changes picture");
    [anna.outbox filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(MeshEvent *e, NSDictionary *b) { return [e hasTag:@"p" value:ben.pubkey]; }]];
    check(anna.outbox.count == 2, "gs + gp to ben");
    MeshEvent *gs = anna.outbox[0], *gp = anna.outbox[1];
    [anna.outbox removeAllObjects];
    [ben.messenger receive:gp];
    check([[ben.messenger groupPicture:gid] isEqualToString:[MeshBase64 encode:pic1]], "gp before state: old picture still shown");
    [ben.messenger receive:gs];
    check([[ben.messenger groupPicture:gid] isEqualToString:[MeshBase64 encode:pic3]], "pending picture applied with matching state");
    [ben.messenger receive:gp];   // derselbe noch einmal: schon erledigt
    check([[ben.messenger groupPicture:gid] isEqualToString:[MeshBase64 encode:pic3]], "replayed gp harmless");
    [anna.outbox removeAllObjects];

    // Zustand mit neuem p, Bild kommt nie: das alte passt nicht mehr -> Identicon
    MeshGroupState *cur = [anna.messenger groupState:gid status:NULL inviter:NULL];
    MeshGroupState *orphan = [cur withPicture:[MeshMessenger groupPictureHash:pic2]];
    check([ben.messenger receive:dmFrom(anna, ben, [MeshEnvelope groupState:[orphan json]])] && ![ben.messenger groupPicture:gid], "stale picture dropped when p changes");
    check(![ben.store groupPicture:gid], "and removed from the store");
    // Das passende Bild danach: angenommen
    check([ben.messenger receive:dmFrom(anna, ben, [MeshEnvelope groupPicture:pic2 gid:gid])]
          && [[ben.messenger groupPicture:gid] isEqualToString:[MeshBase64 encode:pic2]], "matching gp after state accepted");

    // Magic Bytes: "abc" mit passendem p im Zustand wird trotzdem verworfen
    NSData *abc = [@"abc" dataUsingEncoding:NSUTF8StringEncoding];
    check(![anna.messenger setGroupPicture:abc group:gid], "admin can't set non-image");
    MeshGroupState *abcState = [orphan withPicture:[MeshMessenger groupPictureHash:abc]];
    [ben.messenger receive:dmFrom(anna, ben, [MeshEnvelope groupState:[abcState json]])];
    check(![ben.messenger receive:dmFrom(anna, ben, [MeshEnvelope groupPicture:abc gid:gid])] && ![ben.messenger groupPicture:gid], "non-JPEG/PNG rejected");
    NSMutableData *png = [NSMutableData dataWithBytes:"\x89PNG\r\n\x1a\n" length:8];
    [png appendData:fakeJPEG(100, 5)];
    MeshGroupState *pngState = [abcState withPicture:[MeshMessenger groupPictureHash:png]];
    [ben.messenger receive:dmFrom(anna, ben, [MeshEnvelope groupState:[pngState json]])];
    check([ben.messenger receive:dmFrom(anna, ben, [MeshEnvelope groupPicture:png gid:gid])]
          && [[ben.messenger groupPicture:gid] isEqualToString:[MeshBase64 encode:png]], "PNG accepted");

    // Größe: 64 KB ja (auch über den NIP-04-Weg), eins mehr nein
    check(![anna.messenger setGroupPicture:fakeJPEG(64 * 1024 + 1, 2) group:gid], "admin: over 64 KB refused");
    NSData *maxPic = fakeJPEG(64 * 1024, 4);
    [anna.store saveGroup:gid state:[pngState json] status:MeshGroupMember inviter:nil];   // Admin auf Bens Stand
    check([anna.messenger setGroupPicture:maxPic group:gid], "admin sets a 64 KB picture");
    [anna deliverTo:all];
    check([[ben.messenger groupPicture:gid] isEqualToString:[MeshBase64 encode:maxPic]]
          && [[cleo.messenger groupPicture:gid] isEqualToString:[MeshBase64 encode:maxPic]], "64 KB picture arrives at all");

    // Entfernen: Zustand ohne p (r+1), kein gp
    check([anna.messenger setGroupPicture:nil group:gid], "admin removes picture");
    MeshGroupState *gone = [anna.messenger groupState:gid status:NULL inviter:NULL];
    BOOL anyGp = NO;
    for (MeshEvent *e in anna.outbox) {
        Device *to = [e hasTag:@"p" value:ben.pubkey] ? ben : cleo;
        NSString *txt = [MeshNip44 decrypt:e.content keys:to.keys peerXonlyPub:anna.keys.xonlyPub];
        anyGp |= [MeshEnvelope parse:txt].type == MeshEnvelopeGroupPicture;
    }
    check(!gone.picture && ![[gone json] containsString:@"\"p\""] && !anyGp && anna.outbox.count == 2, "removal: state without p, no gp");
    [anna deliverTo:all];
    check(![ben.messenger groupPicture:gid] && ![cleo.messenger groupPicture:gid] && ![anna.messenger groupPicture:gid], "picture removed everywhere");

    // Wartende Bilder nur RAM: nach dem Sperren (wipeKeys) vergessen
    NSData *pic4 = fakeJPEG(500, 6);
    check([anna.messenger setGroupPicture:pic4 group:gid], "admin sets again");
    NSMutableArray *toBen = [NSMutableArray array];
    for (MeshEvent *e in anna.outbox) if ([e hasTag:@"p" value:ben.pubkey]) [toBen addObject:e];
    [anna.outbox removeAllObjects];
    [ben.messenger receive:toBen[1]];   // gp zuerst
    [ben.messenger wipeKeys];
    [ben.messenger receive:toBen[0]];   // dann der Zustand
    check(![ben.messenger groupPicture:gid], "pending picture not kept over lock");
}

#pragma mark - Team-Chat

static MeshEvent *broadcast(MeshKeys *team, NSString *content, NSArray *tags, long long unused) {
    MeshEvent *e = [MeshEvent kind:1 content:content tags:tags];
    [e signWithKeys:team];
    return e;
}

static void testTeam(void) {
    MeshKeys *teamKeys = [MeshKeys generate];
    NSString *teamPk = [MeshHex encode:teamKeys.xonlyPub];
    Device *user = [[Device alloc] initNamed:@"user"];

    check(![MeshTeam teamWithStore:user.store myPubkey:user.pubkey], "placeholder TEAM_PK: team chat off");
    check([MeshTeam isPlaceholder:MeshTeamPubkey] && !MeshTeamCard.length, "constants are placeholders");
    check(![[MeshTeam alloc] initWithStore:user.store myPubkey:user.pubkey teamPubkey:A64('0') card:@""], "64 zeros = off");
    check(![[MeshTeam alloc] initWithStore:user.store myPubkey:teamPk teamPubkey:teamPk card:@""], "own identity is the team: off");

    MeshTeam *team = [[MeshTeam alloc] initWithStore:user.store myPubkey:user.pubkey teamPubkey:teamPk card:@"mesh:npub1xyz"];
    team.delegate = user;
    check(team != nil, "team chat on with real pk");
    [team startWithRelays:nil];
    NSArray *chat = [user.store messagesForChat:MeshTeamChat];
    check(chat.count == 2 && [((MeshMessage *)chat[0]).sender isEqualToString:MeshSenderApp] && ((MeshMessage *)chat[1]).kind == MeshPayloadContact, "greeting + card, local");
    [team startWithRelays:nil];
    check([user.store messagesForChat:MeshTeamChat].count == 2, "greeting only once");
    NSDictionary *f = [team broadcastFilter];
    check([f[@"authors"] isEqual:@[teamPk]] && [f[@"kinds"] isEqual:(@[@1, @5])] && [f[@"since"] longLongValue] <= MeshNow() - 90 * 24 * 3600 + 5, "broadcast filter 90 days");

    // Rundbriefe
    NSString *body = @"{\"v\":1,\"de\":\"Neue Version\",\"en\":\"New version\"}";
    MeshEvent *ok = broadcast(teamKeys, body, @[@[@"t", @"mesh-team"]], 0);
    check([team receiveBroadcast:ok], "broadcast accepted");
    MeshMessage *bm = [user.store messagesForChat:MeshTeamChat].lastObject;
    check([bm.sender isEqualToString:MeshSenderAll] && [bm.content isEqualToString:@"New version"] && !bm.fromMe, "stored as 'to everyone' (device language)");
    check(![team receiveBroadcast:ok], "duplicate broadcast ignored");
    check([[team broadcastFilter][@"since"] longLongValue] == ok.createdAt + 1, "since advances");
    check(![team receiveBroadcast:broadcast(teamKeys, body, @[], 0)], "B6 broadcast without t-tag rejected");
    check(![team receiveBroadcast:broadcast(teamKeys, @"{\"v\":1,\"de\":\"x\1mesh:g:0\"}", @[@[@"t", @"mesh-team"]], 0)], "B6 broadcast with marker rejected");
    MeshKeys *other = [MeshKeys generate];
    check(![team receiveBroadcast:broadcast(other, body, @[@[@"t", @"mesh-team"]], 0)], "broadcast from other key rejected");
    MeshEvent *bad = broadcast(teamKeys, body, @[@[@"t", @"mesh-team"]], 0);
    bad.content = @"{\"v\":1,\"de\":\"verändert\"}";
    check(![team receiveBroadcast:bad], "bad signature rejected");
    MeshEvent *future = [MeshEvent kind:1 content:body tags:@[@[@"t", @"mesh-team"]]];
    future.createdAt = MeshNow() + 3600;
    [future signWithKeys:teamKeys];
    check(future.createdAt <= MeshNow() + 5 || ![team receiveBroadcast:future], "future broadcast rejected");
    check(![team receiveBroadcast:broadcast(teamKeys, @"{\"v\":1,\"de\":\"mesh:img/9j\"}", @[@[@"t", @"mesh-team"]], 0)], "broadcast never parsed as media");
    MeshEvent *del = [MeshEvent kind:5 content:@"" tags:@[@[@"e", ok.eventId]]];
    [del signWithKeys:other];
    check(![team receiveBroadcast:del] && [user.store messageWithKey:ok.eventId chat:MeshTeamChat], "kind 5 from other key ignored");
    del = [MeshEvent kind:5 content:@"" tags:@[@[@"e", ok.eventId]]];
    [del signWithKeys:teamKeys];
    check([team receiveBroadcast:del] && ![user.store messageWithKey:ok.eventId chat:MeshTeamChat], "kind 5 deletes the broadcast");
    check(![team receiveBroadcast:ok], "deleted broadcast stays gone");

    // Anonym: ohne Tor (Mac-Test) keine getrennte Verbindung -> nichts senden
    check(!team.isolationAvailable && ![team send:@"Hallo Team"] && !team.lastSentEvent, "no isolation: nothing sent (fail-closed)");
    check(![user.store queuedTeamEvents].count && ![user.store queuedEvents].count, "nothing queued anywhere");

    // E vorhanden (von früher): Antworten des Teams nur an E, nur NIP-44
    MeshKeys *e = [MeshKeys generate];
    NSData *esk = e.seckey;
    [user.store setTeamKey:[MeshHex encode:esk]];
    [team lock];
    [team startWithRelays:nil];
    NSString *ePk = [MeshHex encode:e.xonlyPub];
    check([[team anonPubkey] isEqualToString:ePk] && ![ePk isEqualToString:user.pubkey], "E loaded, not the identity");
    NSString *reply = [MeshNip44 encrypt:[MeshEnvelope message:@"Danke!" cmid:@"aabbccddeeff0011" replyTo:nil timer:0 mode:MeshTimerFromRead bundle:nil]
                                    keys:teamKeys peerXonlyPub:e.xonlyPub];
    MeshEvent *r = [MeshEvent kind:4 content:reply tags:@[@[@"p", ePk]]];
    [r signWithKeys:teamKeys];
    check([team receiveAnon:r], "reply from team to E accepted");
    MeshMessage *rm = [user.store messagesForChat:MeshTeamChat].lastObject;
    check([rm.content isEqualToString:@"Danke!"] && !rm.sender, "reply is personal (no 'to everyone')");
    check(![team receiveAnon:r], "duplicate reply ignored");
    MeshEvent *fake = [MeshEvent kind:4 content:[MeshNip44 encrypt:@"Fake" keys:other peerXonlyPub:e.xonlyPub] tags:@[@[@"p", ePk]]];
    [fake signWithKeys:other];
    check(![team receiveAnon:fake], "reply from other key rejected");
    MeshEvent *toUser = [MeshEvent kind:4 content:reply tags:@[@[@"p", user.pubkey]]];
    [toUser signWithKeys:teamKeys];
    check(![team receiveAnon:toUser], "only events to E");
    // Ein anonymer Klartext über den normalen Weg wird nie angezeigt
    NSString *anonPlain = [MeshEnvelope anonMessage:@"Bug" cmid:@"00112233aabbccdd"];
    MeshEvent *viaDm = [MeshEvent kind:4 content:[MeshNip44 encrypt:anonPlain keys:other peerXonlyPub:user.keys.xonlyPub] tags:@[@[@"p", user.pubkey]]];
    [viaDm signWithKeys:other];
    check(![user.messenger receive:viaDm] && ![user.store isContact:[MeshHex encode:other.xonlyPub]], "anon envelope on the normal path ignored");

    // Neu anfangen: persönliche weg, Begrüßung bleibt, neuer E
    [team startOver];
    NSArray *left = [user.store messagesForChat:MeshTeamChat];
    BOOL personal = NO;
    for (MeshMessage *m in left) personal |= m.sender == nil;
    check(!personal && left.count == 2 && ![[team anonPubkey] isEqualToString:ePk] && [team anonPubkey].length == 64, "start over: new E, greeting kept");
    check(![team receiveAnon:r], "old E's replies not shown again");

    team.muted = YES; team.hidden = YES;
    check(team.muted && team.hidden, "mute/hide stored");
    [team lock];
    check(![team anonPubkey], "E wiped from RAM on lock");
}

#pragma mark - getrennte Verbindung

static void testIsolatedPool(void) {
    MeshRelayPool *anon = [[MeshRelayPool alloc] initWithURLs:@[@"wss://a"] isolation:@"00112233445566778899aabbccddeeff"];
    MeshRelay *r = [[anon valueForKey:@"relays"] firstObject];
    [anon start];
    check(anon.isolated && [r.socksCredential length] == 32 && r.connectCalls == 0, "isolated pool never connects without Tor");
    [anon stop];
    MeshRelayPool *normal = [[MeshRelayPool alloc] initWithURLs:@[@"wss://a"]];
    MeshRelay *n = [[normal valueForKey:@"relays"] firstObject];
    [normal start];
    check(!normal.isolated && !n.socksCredential && n.connectCalls == 1, "normal pool unchanged");
    [normal stop];
}

#pragma mark - B8 Klarstellungen

static int sqlInt(Device *d, NSString *sql) {
    sqlite3 *db; sqlite3_stmt *st; int v = -1;
    sqlite3_open(d.path.UTF8String, &db);
    if (sqlite3_prepare_v2(db, sql.UTF8String, -1, &st, NULL) == SQLITE_OK && sqlite3_step(st) == SQLITE_ROW) v = sqlite3_column_int(st, 0);
    sqlite3_finalize(st);
    sqlite3_close(db);
    return v;
}

static void sqlRun(Device *d, NSString *sql) {
    sqlite3 *db;
    sqlite3_open(d.path.UTF8String, &db);
    sqlite3_exec(db, sql.UTF8String, NULL, NULL, NULL);
    sqlite3_close(db);
}

static MeshEvent *groupMsg(Device *from, Device *to, NSString *gid, NSString *content, NSString *cmid) {
    return dmFrom(from, to, [MeshEnvelope inGroup:gid plain:[MeshEnvelope message:content cmid:cmid replyTo:nil timer:0 mode:MeshTimerFromRead bundle:nil]]);
}

static NSString *joinGroup(Device *admin, NSArray *members, NSArray *all) {
    NSMutableArray *pks = [NSMutableArray array];
    for (Device *d in members) { [admin befriend:d]; [d befriend:admin]; [pks addObject:d.pubkey]; }
    NSString *gid = [admin.messenger createGroup:@"B8" members:pks myName:@"Admin"];
    [admin deliverTo:all];
    for (Device *d in members) { [d.messenger acceptInvite:gid myName:@"M"]; [d deliverTo:all]; }
    [admin deliverTo:all];
    return gid;
}

static void testB8(void) {
    Device *anna = [[Device alloc] initNamed:@"b8anna"], *ben = [[Device alloc] initNamed:@"b8ben"], *cleo = [[Device alloc] initNamed:@"b8cleo"],
           *dora = [[Device alloc] initNamed:@"b8dora"];
    NSArray *all = @[anna, ben, cleo, dora];
    NSString *gid = joinGroup(anna, @[ben, cleo], all);
    check(statusOf(ben, gid) == MeshGroupMember && statusOf(cleo, gid) == MeshGroupMember, "B8 setup: two members");

    // B8.1: Wiedereinladung eines Ausgetretenen (r+1, Mitglieder unverändert, Zustand an alle)
    [cleo.messenger leaveGroup:gid];
    [cleo deliverTo:all]; [anna deliverTo:all];
    MeshGroupState *before = [anna.messenger groupState:gid status:NULL inviter:NULL];
    check([anna.messenger invite:@[cleo.pubkey] toGroup:gid], "B8.1 admin re-invites who left");
    MeshGroupState *after = [anna.messenger groupState:gid status:NULL inviter:NULL];
    check(after.revision == before.revision + 1 && [after.members isEqualToArray:before.members], "B8.1 r+1, members unchanged");
    BOOL gsToBen = NO, giToCleo = NO;
    for (MeshEvent *e in anna.outbox) {
        Device *to = [e hasTag:@"p" value:ben.pubkey] ? ben : cleo;
        MeshEnvelope *env = [MeshEnvelope parse:[MeshNip44 decrypt:e.content keys:to.keys peerXonlyPub:anna.keys.xonlyPub]];
        gsToBen |= to == ben && env.type == MeshEnvelopeGroupState;
        giToCleo |= to == cleo && env.type == MeshEnvelopeGroupInvite && [env.groupState rangeOfString:[NSString stringWithFormat:@"\"r\":%lld", after.revision]].location != NSNotFound;
    }
    check(gsToBen && giToCleo, "B8.1 state to members, gi carries the new revision");
    [anna deliverTo:all];
    check(statusOf(cleo, gid) == MeshGroupInvited, "B8.1 who left takes the new invitation");
    [cleo.messenger acceptInvite:gid myName:@"Cleo"];
    [cleo deliverTo:all]; [anna deliverTo:all];
    check(statusOf(cleo, gid) == MeshGroupMember, "B8.1 back in the group");

    // B8.2: keine Dateien/Videos in Gruppen
    NSString *file = [MeshPayload contentWithFile:[NSData dataWithBytes:"abc" length:3] name:@"v.mp4" mime:@"video/mp4"];
    check(![MeshMessenger fitsGroup:file] && ![anna.messenger sendGroup:gid content:file replyTo:nil], "B8.2 no video/file sent");
    MeshEvent *fe = groupMsg(anna, ben, gid, file, @"a1a1a1a1a1a1a1a1");
    check(![ben.messenger receive:fe] && [ben.store isDeleted:fe.eventId], "B8.2 file received in group: discarded for good");
    MeshEvent *fc = dmFrom(anna, ben, [@"\1mesh:g:" stringByAppendingFormat:@"%@\n\1mesh:fc:0011223344556677|0|2|x|text/plain|QQ==", gid]);
    check(![ben.messenger receive:fc], "B8.2 file chunk with group header ignored");

    // B8.3: Bild ≤ 256 KB, Sprache ≤ 512 KB (Base64-Länge des Inhalts)
    NSString *img = [MeshPayload contentWithImage:fakeJPEG(150 * 1024, 1)];
    NSString *bigImg = [MeshPayload contentWithImage:fakeJPEG(200 * 1024, 1)];
    check(img.length <= 256 * 1024 && bigImg.length > 256 * 1024, "B8.3 test sizes");
    check([MeshMessenger fitsGroup:img] && ![MeshMessenger fitsGroup:bigImg], "B8.3 image limit");
    check(![anna.messenger sendGroup:gid content:bigImg replyTo:nil] && !anna.outbox.count, "B8.3 oversized image not sent");
    NSString *voice = [MeshPayload contentWithVoice:[NSMutableData dataWithLength:300 * 1024] seconds:30];
    NSString *bigVoice = [MeshPayload contentWithVoice:[NSMutableData dataWithLength:400 * 1024] seconds:30];
    check([MeshMessenger fitsGroup:voice] && ![MeshMessenger fitsGroup:bigVoice], "B8.3 voice limit");
    MeshEvent *bi = [MeshEvent kind:4 content:[MeshNip04 encrypt:[MeshEnvelope inGroup:gid plain:[MeshEnvelope message:bigImg cmid:@"b2b2b2b2b2b2b2b2" replyTo:nil timer:0 mode:MeshTimerFromRead bundle:nil]]
                                                         sharedX:[anna.keys ecdhSharedX:ben.keys.xonlyPub]] tags:@[@[@"p", ben.pubkey]]];
    [bi signWithKeys:anna.keys];
    check(![ben.messenger receive:bi] && ![ben.store hasMessageWithKey:@"b2b2b2b2b2b2b2b2" chat:MeshGroupChat(gid)], "B8.3 oversized image received: discarded");
    MeshMessage *okImg = [anna.messenger sendGroup:gid content:img replyTo:nil];
    [anna deliverTo:all];
    check(okImg && [ben.store hasMessageWithKey:okImg.cmid chat:MeshGroupChat(gid)], "B8.3 image within limit arrives");

    // B8.4: Nachricht vor dem passenden Zustand -> gepuffert (ohne Vermerk), nach dem Zustand angezeigt
    [dora befriend:anna]; [anna befriend:dora];
    [anna.messenger invite:@[dora.pubkey] toGroup:gid];
    [anna deliverTo:all];
    [dora.messenger acceptInvite:gid myName:@"Dora"];
    MeshEvent *early = groupMsg(ben, dora, gid, @"willkommen", @"c3c3c3c3c3c3c3c3");
    check(![dora.messenger receive:early] && ![dora.store isDeleted:early.eventId], "B8.4 early message buffered, not tombstoned");
    MeshEvent *earlyReact = dmFrom(ben, dora, [MeshEnvelope inGroup:gid plain:[MeshEnvelope reactionTo:@"c3c3c3c3c3c3c3c3" emoji:@"👍"]]);
    [dora.messenger receive:earlyReact];
    check(![dora.store isDeleted:earlyReact.eventId] && [[dora.messenger valueForKey:@"pendingGroupEvents"][gid] count] == 2, "B8.4 reaction buffered too");
    [dora deliverTo:all]; [anna deliverTo:all];   // Admin nimmt auf, Zustand an alle
    MeshMessage *shown = [dora.store messageWithKey:@"c3c3c3c3c3c3c3c3" chat:MeshGroupChat(gid)];
    check(statusOf(dora, gid) == MeshGroupMember && [shown.content isEqualToString:@"willkommen"] && [shown.sender isEqualToString:ben.pubkey],
          "B8.4 buffered message shown after the state");
    check([shown.reactPeer isEqualToString:@"👍"] && ![[dora.messenger valueForKey:@"pendingGroupEvents"][gid] count], "B8.4 buffered reaction applied, buffer empty");
    MeshEvent *unknownGid = groupMsg(ben, dora, @"ffffffffffffffff", @"?", @"d4d4d4d4d4d4d4d4");
    check(![dora.messenger receive:unknownGid] && [dora.store isDeleted:unknownGid.eventId], "B8.4 unknown gid: discarded for good");
    // Höchstens 50 je Gruppe, 15 Minuten
    NSString *g2 = joinGroup(anna, @[ben], all);
    [cleo befriend:anna]; [anna befriend:cleo];
    [anna.messenger invite:@[cleo.pubkey] toGroup:g2];
    [anna deliverTo:all];   // Cleo: Einladung offen
    NSMutableArray *sent = [NSMutableArray array];
    for (int i = 0; i < 55; i++) {
        MeshEvent *e = groupMsg(ben, cleo, g2, [NSString stringWithFormat:@"m%d", i], [NSString stringWithFormat:@"%016x", 0x100 + i]);
        [sent addObject:e];
        [cleo.messenger receive:e];
    }
    BOOL anyTomb = NO;
    for (MeshEvent *e in sent) anyTomb |= [cleo.store isDeleted:e.eventId];
    check(!anyTomb, "B8.4 nothing tombstoned while buffering");
    NSMutableArray *buf = [cleo.messenger valueForKey:@"pendingGroupEvents"][g2];
    check(buf.count == 50, "B8.4 at most 50 per group");
    for (NSUInteger i = 0; i < buf.count; i++) if (i < 10) [buf[i] setValue:@(MeshNow() - 16 * 60) forKey:@"arrived"];
    [cleo.messenger acceptInvite:g2 myName:@"Cleo"];
    [cleo deliverTo:all]; [anna deliverTo:all];
    check(statusOf(cleo, g2) == MeshGroupMember && [cleo.store messagesForChat:MeshGroupChat(g2)].count >= 40
          && ![cleo.store hasMessageWithKey:[NSString stringWithFormat:@"%016x", 0x100] chat:MeshGroupChat(g2)], "B8.4 older than 15 min dropped, rest shown");
    // Verlassen: endgültig verwerfen
    [cleo.messenger leaveGroup:g2];
    MeshEvent *afterLeave = groupMsg(ben, cleo, g2, @"noch da?", @"e5e5e5e5e5e5e5e5");
    check(![cleo.messenger receive:afterLeave] && [cleo.store isDeleted:afterLeave.eventId], "B8.4 left: discarded for good");
    // Sperren: Puffer weg
    [dora.messenger receive:groupMsg(ben, dora, @"0123012301230123", @"x", @"f6f6f6f6f6f6f6f6")];
    [ben.messenger wipeKeys];
    check(![[ben.messenger valueForKey:@"pendingGroupEvents"] count], "B8.4 buffer is RAM only (cleared on lock)");

    // B8.5: Einladung von einem (noch) nicht angenommenen Absender: zurückhalten, nicht zeigen, ohne Vermerk
    Device *eve = [[Device alloc] initNamed:@"b8eve"], *fred = [[Device alloc] initNamed:@"b8fred"];
    NSArray *ef = @[eve, fred];
    [eve befriend:fred];   // Fred hat Eve nicht angenommen
    NSString *g3 = [eve.messenger createGroup:@"Später" members:@[fred.pubkey] myName:@"Eve"];
    MeshEvent *gi = eve.outbox.lastObject;
    [eve deliverTo:ef];
    check(statusOf(fred, g3) == (MeshGroupStatus)-1 && ![fred.store isDeleted:gi.eventId] && [fred.store heldInviteCount] == 1, "B8.5 held, not shown, not tombstoned");
    check(sqlInt(fred, @"SELECT COUNT(*) FROM held_invites WHERE instr(data, 'Später') > 0 OR instr(data, 'enc2:') = 0") == 0, "B8.5 held invite sealed");
    [fred.messenger receive:gi];
    check([fred.store heldInviteCount] == 1, "B8.5 same invite held once");
    [fred befriend:eve];
    check([fred.messenger contactAccepted:eve.pubkey] && statusOf(fred, g3) == MeshGroupInvited && ![fred.store heldInviteCount], "B8.5 shown once the contact is accepted");
    check([fred.messenger acceptInvite:g3 myName:@"Fred"], "B8.5 and can be joined");
    // Höchstens 20, älter als 30 Tage weg, Blockierte weg
    Device *gina = [[Device alloc] initNamed:@"b8gina"];
    for (int i = 0; i < 24; i++) {
        MeshKeys *k = [MeshKeys generate];
        MeshGroupState *st = [MeshGroupState stateWithGroup:[NSString stringWithFormat:@"%016x", 0xabc000 + i] name:@"Spam" admin:[MeshHex encode:k.xonlyPub] adminName:@""];
        MeshEvent *e = [MeshEvent kind:4 content:[MeshNip44 encrypt:[MeshEnvelope groupInvite:[st json]] keys:k peerXonlyPub:gina.keys.xonlyPub] tags:@[@[@"p", gina.pubkey]]];
        [e signWithKeys:k];
        [gina.messenger receive:e];
    }
    check([gina.store heldInviteCount] == 20 && ![gina.store groupIds].count, "B8.5 at most 20 held");
    sqlRun(gina, [NSString stringWithFormat:@"UPDATE held_invites SET at=%lld WHERE id IN (SELECT id FROM held_invites ORDER BY id LIMIT 5)", MeshNow() - 31 * 24 * 3600]);
    [gina.messenger maintainGroups];
    check([gina.store heldInviteCount] == 15, "B8.5 older than 30 days forgotten");

    // B8.6: gleiche Säuberung für n, nm und den Beitrittsnamen
    NSMutableDictionary *o = [[MeshJSON objectWithData:[[after json] dataUsingEncoding:NSUTF8StringEncoding]] mutableCopy];
    unichar shy[] = { 'F', 0xAD, 'a', 0x2060, 'm', ' ', ' ', 'X', 0x200D };
    o[@"n"] = [NSString stringWithCharacters:shy length:9];
    MeshGroupState *clean = [MeshGroupState stateFromObject:o];
    check([clean.name isEqualToString:[NSString stringWithFormat:@"Fam  X%C", (unichar)0x200D]], "B8.6 group name: Cf removed, ZWJ and inner spaces kept");
    MeshGroupState *withLong = [clean withMember:A64('7') name:[@"" stringByPaddingToLength:45 withString:@"j" startingAtIndex:0]];
    check([withLong nameOf:A64('7')].length == 40, "B8.6 join name truncated to 40");

    // B8.7: gl vom Admin allein (Android sendet beim Auflösen evtl. nur gs, iPod beides) = aufgelöst
    MeshEvent *gl = dmFrom(eve, fred, [MeshEnvelope groupLeave:g3]);
    [fred.store setGroupStatus:MeshGroupMember gid:g3];
    check([fred.messenger receive:gl] && statusOf(fred, g3) == MeshGroupMember && ![fred.store isDeleted:gl.eventId], "B9 admin gl held (transfer may follow), not tombstoned");
    [[fred.messenger valueForKey:@"heldGroupControl"][g3] setValue:@(MeshNow() - 15 * 60) forKey:@"leaveAt"];
    check([fred.messenger secondsUntilNextExpiry] == 0 && [fred.messenger deleteExpired] && statusOf(fred, g3) == MeshGroupDissolved, "B8.7 admin gl dissolves after 15 min without transfer");
    NSString *g4 = [eve.messenger createGroup:@"Weg" members:@[fred.pubkey] myName:@"Eve"];
    [eve deliverTo:ef];
    check(statusOf(fred, g4) == MeshGroupInvited, "B8.7 setup: invited");
    check([fred.messenger receive:dmFrom(eve, fred, [MeshEnvelope groupLeave:g4])] && statusOf(fred, g4) == (MeshGroupStatus)-1, "B8.7 admin gl drops an open invitation");
    // Admin löst auf: gs(m=[]) UND gl, auch an offen Eingeladene
    NSString *g5 = joinGroup(anna, @[ben], all);
    [anna.messenger invite:@[dora.pubkey] toGroup:g5];
    [anna deliverTo:all];
    check(statusOf(dora, g5) == MeshGroupInvited, "B8.7 setup: dora invited");
    check([anna.messenger deletingDissolves:g5] && ![ben.messenger deletingDissolves:g5], "B8.8 only the admin's delete dissolves");
    [anna.messenger leaveGroup:g5];
    int gs = 0, gls = 0;
    for (MeshEvent *e in anna.outbox) {
        Device *to = [e hasTag:@"p" value:ben.pubkey] ? ben : dora;
        MeshEnvelope *env = [MeshEnvelope parse:[MeshNip44 decrypt:e.content keys:to.keys peerXonlyPub:anna.keys.xonlyPub]];
        gs += env.type == MeshEnvelopeGroupState; gls += env.type == MeshEnvelopeGroupLeave;
    }
    check(gs == 2 && gls == 2, "B8.7 admin sends gs(m=[]) and gl to member and invitee");
    [anna deliverTo:all];
    check(statusOf(ben, g5) == MeshGroupDissolved && statusOf(dora, g5) == (MeshGroupStatus)-1, "B8.7 dissolved for the member, invitation gone");

    // B8.8: Admin löscht den Chat einer aktiven Gruppe -> für alle aufgelöst
    NSString *g6 = joinGroup(anna, @[ben], all);
    check([anna.messenger deleteGroup:g6] && statusOf(anna, g6) == (MeshGroupStatus)-1, "B8.8 admin deletes the chat");
    [anna deliverTo:all];
    check(statusOf(ben, g6) == MeshGroupDissolved, "B8.8 ... and the group is dissolved for everyone");
}

#pragma mark - Fan-out

static void spinOnce(void) { [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]]; }

static int queued(Device *d) { return sqlInt(d, @"SELECT COUNT(*) FROM outbox"); }

static void testFanout(void) {
    Device *anna = [[Device alloc] initNamed:@"fanna"];
    NSMutableArray *members = [NSMutableArray array], *all = [NSMutableArray arrayWithObject:anna];
    for (int i = 0; i < 4; i++) { Device *d = [[Device alloc] initNamed:[NSString stringWithFormat:@"fm%d", i]]; [members addObject:d]; [all addObject:d]; }
    NSString *gid = joinGroup(anna, members, all);
    [anna.outbox removeAllObjects];
    sqlRun(anna, @"DELETE FROM outbox");

    // Schrittweise: die erste Kopie sofort, dann je Runloop-Durchgang eine
    MeshMessage *m = [anna.messenger sendGroup:gid content:@"Hallo alle" replyTo:nil];
    check(m && anna.outbox.count == 1 && [[anna.messenger valueForKey:@"fanoutJobs"] count] == 1, "fan-out: first copy at once, rest queued");
    [anna.messenger fanoutStep];
    check(anna.outbox.count == 2, "fan-out: one copy per step");
    for (int i = 0; i < 20 && anna.outbox.count < 4; i++) spinOnce();
    check(anna.outbox.count == 4 && ![[anna.messenger valueForKey:@"fanoutJobs"] count], "fan-out: all four copies built");
    check(sqlInt(anna, [NSString stringWithFormat:@"SELECT COUNT(*) FROM fanout WHERE message_rowid=%lld", m.rowId]) == 4, "fan-out ids persisted for every copy");

    // Zwei Haken, sobald irgendeine Kopie bestätigt ist (auch eine spätere), und das übersteht ein Sperren
    MeshEvent *third = anna.outbox[2];
    MeshStore *reopened = [MeshStore new];
    [reopened openAtPath:anna.path];
    NSMutableData *k = [anna.store valueForKey:@"key"];
    [reopened setDataKey:k];
    check([reopened markFanoutDelivered:third.eventId], "later copy confirmed after reopen");
    check(((MeshMessage *)[reopened messagesForChat:MeshGroupChat(gid)].lastObject).status == MeshMessageDelivered, "message shows delivered");
    check(![reopened markFanoutDelivered:third.eventId], "confirmation counted once");
    check(queued(anna) == 3, "confirmed copy left the queue");

    // Löschen nimmt alle noch wartenden Kopien aus der Warteschlange
    [anna.store deleteMessage:m.rowId];
    check(queued(anna) == 0 && sqlInt(anna, @"SELECT COUNT(*) FROM fanout") == 0, "delete: all copies leave the outbox");

    // Löschen mitten im Fan-out: keine weiteren Kopien
    [anna.outbox removeAllObjects];
    MeshMessage *m2 = [anna.messenger sendGroup:gid content:@"gleich weg" replyTo:nil];
    [anna.store deleteMessage:m2.rowId];
    [anna.messenger finishPendingSends];
    check(anna.outbox.count == 1 && queued(anna) == 0, "deleted during fan-out: no more copies, queue empty");

    // Ablauf (Selbstlöschen) und Chat leeren erfassen alle Kopien
    MeshMessage *m3 = [anna.messenger sendGroup:gid content:@"läuft ab" replyTo:nil];
    [anna.messenger finishPendingSends];
    check(queued(anna) == 4, "four copies waiting");
    sqlRun(anna, [NSString stringWithFormat:@"UPDATE messages SET expires=%lld WHERE rowid=%lld", MeshNow() - 1, m3.rowId]);
    check([anna.messenger deleteExpired] && queued(anna) == 0, "expiry: all copies leave the outbox");
    [anna.messenger sendGroup:gid content:@"leeren" replyTo:nil];
    [anna.messenger finishPendingSends];
    [anna.store clearChat:MeshGroupChat(gid) at:MeshNow()];
    check(queued(anna) == 0, "clear chat: all copies leave the outbox");

    // Abgelaufene Warteschlange: fehlgeschlagen nur, wenn keine Kopie ankam
    MeshMessage *m4 = [anna.messenger sendGroup:gid content:@"alt" replyTo:nil];
    [anna.messenger finishPendingSends];
    check([anna.store expireQueuedBefore:MeshNow() + 10] && ((MeshMessage *)[anna.store messagesForChat:MeshGroupChat(gid)].lastObject).status == MeshMessageFailed
          && m4 && !sqlInt(anna, @"SELECT COUNT(*) FROM fanout"), "outbox expiry marks failed, fan-out rows cleaned");

    // Verlassen: noch nicht bestätigte Kopien gehen nicht mehr hinaus
    [anna.messenger sendGroup:gid content:@"tschüss" replyTo:nil];
    Device *ben = members[0];
    sqlRun(ben, @"DELETE FROM outbox");
    MeshMessage *fromBen = [ben.messenger sendGroup:gid content:@"von ben" replyTo:nil];
    int benQueued = queued(ben);
    [ben.messenger leaveGroup:gid];
    check(benQueued == 1 && sqlInt(ben, @"SELECT COUNT(*) FROM fanout") == 0 && [[ben.messenger valueForKey:@"fanoutJobs"] count] == 0
          && queued(ben) == 4, "leave: own unsent copies and pending steps dropped, only gl queued");
    check([ben.store messageWithKey:fromBen.cmid chat:MeshGroupChat(gid)].status == MeshMessageFailed, "leave: unsent message marked failed");
    // Gruppe löschen (Admin, löst auf): Kopien weg, Auflösung bleibt in der Warteschlange
    [anna.messenger finishPendingSends];
    [anna.messenger deleteGroup:gid];
    check(!sqlInt(anna, @"SELECT COUNT(*) FROM fanout") && queued(anna) == 8, "delete group: message copies gone, gs+gl to 4 members queued");

    // Sperren mitten im Fan-out: MeshIdentity lock baut vorher alles (finishPendingSends)
    NSString *g2 = joinGroup(anna, members, all);
    [anna.outbox removeAllObjects];
    [anna.messenger sendGroup:g2 content:@"vor dem Sperren" replyTo:nil];
    check(anna.outbox.count == 1, "lock: one copy before");
    [anna.messenger finishPendingSends];
    [anna.messenger wipeKeys];
    check(anna.outbox.count == 4 && ![[anna.messenger valueForKey:@"fanoutJobs"] count], "lock: all copies built synchronously before the keys go");
}

#pragma mark - B9/B10

// Nur die Events an "to" zustellen (Reihenfolge steuern); der Rest bleibt in der Warteschlange.
static int deliverOnly(Device *from, Device *to) {
    [from.messenger finishPendingSends];
    int changed = 0;
    NSMutableArray *rest = [NSMutableArray array];
    for (MeshEvent *e in from.outbox) {
        if ([e hasTag:@"p" value:to.pubkey]) changed += [to.messenger receive:e] ? 1 : 0;
        else [rest addObject:e];
    }
    [from.outbox setArray:rest];
    return changed;
}

static MeshEnvelope *opened(MeshEvent *e, Device *to, Device *from) {
    return [MeshEnvelope parse:[MeshNip44 decrypt:e.content keys:to.keys peerXonlyPub:from.keys.xonlyPub]];
}

static MeshGroupState *stateOf(Device *d, NSString *gid) { return [d.messenger groupState:gid status:NULL inviter:NULL]; }

static MeshPayload *lastNotice(Device *d, NSString *gid) {
    for (MeshMessage *m in [[d.store messagesForChat:MeshGroupChat(gid)] reverseObjectEnumerator])
        if (m.kind == MeshPayloadNotice) return [MeshPayload parseNotice:m.content];
    return nil;
}

static void testB9B10Vectors(void) {
    NSString *a = A64('a'), *c = A64('c');
    MeshEnvelope *e = [MeshEnvelope parse:[NSString stringWithFormat:@"\1mesh:gpr:0123456789abcdef|%@|Q2Fyb2w=", c]];
    check(e.type == MeshEnvelopeGroupPropose && [e.group isEqualToString:@"0123456789abcdef"] && [e.subject isEqualToString:c]
          && [e.subjectName isEqualToString:@"Carol"], "B9 gpr vector");
    check([[MeshEnvelope groupPropose:@"0123456789abcdef" candidate:c name:@"Carol"] isEqualToString:[NSString stringWithFormat:@"\1mesh:gpr:0123456789abcdef|%@|Q2Fyb2w=", c]], "B9 gpr built");
    e = [MeshEnvelope parse:[NSString stringWithFormat:@"\1mesh:gvo:0123456789abcdef|%@|VGVzdA==", a]];
    check(e.type == MeshEnvelopeGroupVouch && [e.group isEqualToString:@"0123456789abcdef"] && [e.subject isEqualToString:a]
          && [e.subjectName isEqualToString:@"Test"], "B9 gvo vector");
    check([[MeshEnvelope groupVouch:@"0123456789abcdef" admin:a groupName:@"Test"] isEqualToString:[NSString stringWithFormat:@"\1mesh:gvo:0123456789abcdef|%@|VGVzdA==", a]], "B9 gvo built");
    check([MeshEnvelope parse:[NSString stringWithFormat:@"\1mesh:gpr:0123456789abcdef|%@", c]].type == MeshEnvelopeIgnored, "gpr without name field ignored");
    check([MeshEnvelope parse:@"\1mesh:gpr:0123456789abcdef|abc|Q2Fyb2w="].type == MeshEnvelopeIgnored, "gpr bad pk ignored");
    check([MeshEnvelope parse:[NSString stringWithFormat:@"\1mesh:mb:x\n\1mesh:gvo:0123456789abcdef|%@|VGVzdA==", a]].type == MeshEnvelopeIgnored, "gvo with bundle ignored");

    NSString *link = [NSString stringWithFormat:@"meshg:1:0123456789abcdef:%@:00112233445566778899aabbccddeeff", a];
    MeshGroupLink *l = [MeshGroupLink parse:link];
    check([l.gid isEqualToString:@"0123456789abcdef"] && [l.admin isEqualToString:a] && [l.key isEqualToString:@"00112233445566778899aabbccddeeff"], "B10 link vector");
    check([[MeshGroupLink linkWithGroup:@"0123456789abcdef" admin:a key:@"00112233445566778899aabbccddeeff"] isEqualToString:link], "B10 link built");
    check([[MeshGroupLink parse:[@"  " stringByAppendingString:link.uppercaseString]].text isEqualToString:link], "link: trimmed, lowercased");
    check(![MeshGroupLink parse:[link stringByAppendingString:@"0"]] && ![MeshGroupLink parse:[link stringByReplacingOccurrencesOfString:@"meshg:1" withString:@"meshg:2"]]
          && ![MeshGroupLink parse:[link stringByAppendingString:@":x"]], "invalid links rejected");
    e = [MeshEnvelope parse:@"\1mesh:gj:0123456789abcdef|QmVu|00112233445566778899aabbccddeeff"];
    check(e.type == MeshEnvelopeGroupJoin && [e.joinName isEqualToString:@"Ben"] && [e.joinKey isEqualToString:@"00112233445566778899aabbccddeeff"], "B10 gj with k vector");
    check([[MeshEnvelope groupJoin:@"0123456789abcdef" name:@"Ben" key:@"00112233445566778899aabbccddeeff"] isEqualToString:@"\1mesh:gj:0123456789abcdef|QmVu|00112233445566778899aabbccddeeff"], "B10 gj with k built");
    check(![MeshEnvelope parse:@"\1mesh:gj:0123456789abcdef|QmVu"].joinKey, "gj without k: no key");
    check([MeshEnvelope parse:@"\1mesh:gj:0123456789abcdef|QmVu|0011"].type == MeshEnvelopeIgnored, "gj with short k ignored");
    e = [MeshEnvelope parse:@"\1mesh:gk:0123456789abcdef|00112233445566778899AABBCCDDEEFF"];
    check(e.type == MeshEnvelopeGroupKey && [e.joinKey isEqualToString:@"00112233445566778899aabbccddeeff"], "gk parses");
    e = [MeshEnvelope parse:@"\1mesh:gk:0123456789abcdef|"];
    check(e.type == MeshEnvelopeGroupKey && [e.joinKey isEqualToString:@""], "gk empty = closed");

    // Zustand mit o: wie B6 plus ,"o":1 nach "tm" (vor p)
    NSString *b = A64('b');
    NSString *b6 = [NSString stringWithFormat:@"{\"v\":1,\"g\":\"0123456789abcdef\",\"n\":\"Test\",\"a\":\"%@\",\"r\":2,\"m\":[\"%@\",\"%@\"],"
                    "\"nm\":{\"%@\":\"Anna\",\"%@\":\"Ben\"},\"t\":0,\"tm\":\"read\"}", a, a, b, a, b];
    NSString *withO = [[b6 substringToIndex:b6.length - 1] stringByAppendingString:@",\"o\":1}"];
    MeshGroupState *s = stateFrom(withO);
    check(s.open && [[s json] isEqualToString:withO], "B10 state with o byte-exact");
    check(!stateFrom(b6).open && [[stateFrom(b6) json] isEqualToString:b6], "B6 without o unchanged");
    MeshGroupState *built = [stateFrom([b6 stringByReplacingOccurrencesOfString:@"\"r\":2" withString:@"\"r\":1"]) withOpen:YES];
    check([[built json] isEqualToString:withO], "B10 state with o built (r 1 -> 2)");
    NSString *oAndP = [[withO substringToIndex:withO.length - 1] stringByAppendingString:@",\"p\":\"ba7816bf8f01cfea\"}"];
    check([[stateFrom(oAndP) json] isEqualToString:oAndP], "o before p");
    NSMutableDictionary *o = [[MeshJSON objectWithData:[withO dataUsingEncoding:NSUTF8StringEncoding]] mutableCopy];
    o[@"o"] = @0;
    check([MeshGroupState stateFromObject:o] && ![MeshGroupState stateFromObject:o].open, "o 0 = closed");
    o[@"o"] = @2;
    check(![MeshGroupState stateFromObject:o], "o 2 rejected");
    o[@"o"] = @YES;
    check(![MeshGroupState stateFromObject:o], "o true rejected");
    o[@"o"] = @"1";
    check(![MeshGroupState stateFromObject:o], "o string rejected");
    o[@"o"] = @1; o[@"m"] = @[];
    check(![MeshGroupState stateFromObject:o], "o with m=[] rejected");
    check(![[s withAdmin:b] open] && [[s withAdmin:b].admin isEqualToString:b] && [s withAdmin:b].revision == 3, "transfer: r+1, new a, closed");
    check(![s withAdmin:A64('c')] && ![s withAdmin:a], "transfer only to another member");

    // Link-Karte
    NSString *card = [MeshPayload contentWithGroupLinkName:@"Test" link:link];
    check([card isEqualToString:[NSString stringWithFormat:@"\1mesh:glink:VGVzdA==\n%@", link]], "glink card built");
    MeshPayload *p = [MeshPayload parse:card];
    check(p.kind == MeshPayloadGroupLink && [p.text isEqualToString:@"Test"] && [p.code isEqualToString:link], "glink card parsed");
    e = [MeshEnvelope parse:[MeshEnvelope message:card cmid:@"00112233aabbccdd" replyTo:nil timer:0 mode:MeshTimerFromRead bundle:nil]];
    check(e.type == MeshEnvelopeMessage && [e.content isEqualToString:card], "glink card travels as a message");
    check([MeshEnvelope parse:[card stringByAppendingString:@"\1mesh:gl:0123456789abcdef"]].type == MeshEnvelopeIgnored, "glink card with another marker ignored");
    check(![MeshMessenger fitsGroup:card], "glink card not in groups");
}

static void testB9Transfer(void) {
    Device *anna = [[Device alloc] initNamed:@"b9anna"], *ben = [[Device alloc] initNamed:@"b9ben"], *cleo = [[Device alloc] initNamed:@"b9cleo"],
           *dora = [[Device alloc] initNamed:@"b9dora"];
    NSArray *all = @[anna, ben, cleo, dora];
    NSString *gid = joinGroup(anna, @[ben, cleo], all);
    [anna befriend:dora]; [dora befriend:anna];
    [anna.messenger invite:@[dora.pubkey] toGroup:gid];
    [anna deliverTo:all];
    check(statusOf(dora, gid) == MeshGroupInvited && [anna.messenger pendingInvitesForGroup:gid].count == 1, "B9 setup: dora invited");

    // Zustand eines Nicht-Admins, der sich zum Admin macht: nicht übernommen, wartet (ohne Vermerk)
    MeshGroupState *cur = stateOf(anna, gid);
    MeshEvent *forged = dmFrom(ben, cleo, [MeshEnvelope groupState:[[cur withAdmin:ben.pubkey] json]]);
    check(![cleo.messenger receive:forged] && [stateOf(cleo, gid).admin isEqualToString:anna.pubkey] && ![cleo.store isDeleted:forged.eventId],
          "B9 transfer from non-admin rejected (held, not tombstoned)");
    NSMutableDictionary *badObj = [[MeshJSON objectWithData:[[cur json] dataUsingEncoding:NSUTF8StringEncoding]] mutableCopy];
    badObj[@"a"] = dora.pubkey; badObj[@"r"] = @(cur.revision + 1);
    MeshEvent *toOutsider = dmFrom(anna, cleo, [MeshEnvelope groupState:[[NSString alloc] initWithData:[MeshJSON dataWithObject:badObj] encoding:NSUTF8StringEncoding]]);
    check(![cleo.messenger receive:toOutsider] && [stateOf(cleo, gid).admin isEqualToString:anna.pubkey], "B9 new admin not in m rejected");
    check(![ben.messenger transferAdmin:cleo.pubkey group:gid leave:NO], "only the admin transfers");
    check(![anna.messenger transferAdmin:dora.pubkey group:gid leave:NO], "transfer only to a member (not an invitee)");

    check([anna.messenger transferAdmin:ben.pubkey group:gid leave:NO], "B9 admin transfers to ben");
    MeshGroupState *t = stateOf(anna, gid);
    check([t.admin isEqualToString:ben.pubkey] && t.revision == cur.revision + 1 && ![anna.messenger pendingInvitesForGroup:gid].count, "B9 r+1, new a, old admin forgot invites");
    int toDora = 0;
    for (MeshEvent *e in anna.outbox) if ([e hasTag:@"p" value:dora.pubkey] && opened(e, dora, anna).type == MeshEnvelopeGroupState) toDora++;
    check(toDora == 1, "B9 transfer state also goes to open invitations");
    [anna deliverTo:all];
    check([stateOf(ben, gid).admin isEqualToString:ben.pubkey] && lastNotice(ben, gid).groupNotice == MeshGroupNoticeYouAdmin, "B9 ben is admin: \"You are now admin\"");
    check([stateOf(cleo, gid).admin isEqualToString:ben.pubkey] && lastNotice(cleo, gid).groupNotice == MeshGroupNoticeNewAdmin, "B9 cleo: \"<Name> is now admin\"");
    check(statusOf(dora, gid) == MeshGroupInviteExpired && lastNotice(dora, gid).groupNotice == MeshGroupNoticeInviteExpired, "B9 dora: invitation expired");
    check(![dora.messenger acceptInvite:gid myName:@"Dora"], "expired invitation can't be joined");

    // Autorität danach nur beim neuen Admin
    MeshEvent *oldRename = dmFrom(anna, cleo, [MeshEnvelope groupState:[[stateOf(anna, gid) renamed:@"Alt"] json]]);
    check(![anna.messenger renameGroup:gid to:@"Alt"] && ![anna.messenger removeMember:cleo.pubkey fromGroup:gid], "old admin can't change the group");
    check(![cleo.messenger receive:oldRename] && [stateOf(cleo, gid).name isEqualToString:@"B8"], "state signed by old admin rejected");
    check([ben.messenger renameGroup:gid to:@"Neu"], "new admin renames");
    [ben deliverTo:all];
    check([stateOf(cleo, gid).name isEqualToString:@"Neu"] && [stateOf(anna, gid).name isEqualToString:@"Neu"], "members take the new admin's state");
    NSData *pic = fakeJPEG(500, 3);
    check([ben.messenger setGroupPicture:pic group:gid], "new admin sets the picture");
    [ben deliverTo:all];
    check([[cleo.messenger groupPicture:gid] isEqualToString:[MeshBase64 encode:pic]], "B7 gp from the new admin accepted");
    MeshEvent *oldGp = dmFrom(anna, cleo, [MeshEnvelope groupPicture:fakeJPEG(400, 4) gid:gid]);
    check(![cleo.messenger receive:oldGp], "gp from the old admin rejected");
    MeshEvent *bufMsg = groupMsg(anna, cleo, gid, @"hallo", @"9a9a9a9a9a9a9a9a");
    check([cleo.messenger receive:bufMsg], "old admin is a normal member (messages accepted)");
    // gl des alten Admins ist jetzt ein normaler Austritt
    [anna.messenger leaveGroup:gid];
    [anna deliverTo:all]; [ben deliverTo:all];
    check(statusOf(cleo, gid) == MeshGroupMember && ![stateOf(cleo, gid) hasMember:anna.pubkey] && ![stateOf(ben, gid) hasMember:anna.pubkey],
          "old admin's gl = normal leave, new admin removes him");
    // Neuer Admin lädt die abgelaufene Einladung neu ein
    [ben befriend:dora]; [dora befriend:ben];
    check([ben.messenger invite:@[dora.pubkey] toGroup:gid], "new admin invites again");
    [ben deliverTo:all];
    check(statusOf(dora, gid) == MeshGroupInvited, "expired invitation replaced by the new admin's");
    // Übergeben und austreten: gl erst nach Zustellung des Übergabe-Zustands
    Device *eve = [[Device alloc] initNamed:@"b9eve"], *fred = [[Device alloc] initNamed:@"b9fred"], *gina = [[Device alloc] initNamed:@"b9gina"];
    NSArray *efg = @[eve, fred, gina];
    NSString *g2 = joinGroup(eve, @[fred, gina], efg);
    check([eve.messenger transferAdmin:fred.pubkey group:g2 leave:YES] && statusOf(eve, g2) == MeshGroupLeft, "B9 transfer and leave");
    NSMutableDictionary *gsIds = [NSMutableDictionary dictionary];
    int gls = 0;
    for (MeshEvent *e in eve.outbox) {
        Device *to = [e hasTag:@"p" value:fred.pubkey] ? fred : gina;
        MeshEnvelope *env = opened(e, to, eve);
        if (env.type == MeshEnvelopeGroupState) gsIds[to.pubkey] = e.eventId;
        gls += env.type == MeshEnvelopeGroupLeave;
    }
    check(gsIds.count == 2 && gls == 0, "B9 gl deferred until the transfer state is delivered");
    check(sqlInt(eve, @"SELECT COUNT(*) FROM group_records WHERE kind=5 AND substr(data,1,5)='enc2:'") == 2, "deferred gl stored sealed");
    [eve deliverTo:efg];
    check([eve.messenger eventStored:gsIds[gina.pubkey]], "relay confirmed gina's copy -> gl to gina");
    int glToGina = 0, glToFred = 0;
    for (MeshEvent *e in eve.outbox) {
        if ([e hasTag:@"p" value:gina.pubkey] && opened(e, gina, eve).type == MeshEnvelopeGroupLeave) glToGina++;
        if ([e hasTag:@"p" value:fred.pubkey]) glToFred++;
    }
    check(glToGina == 1 && glToFred == 0, "gl only to whom the transfer reached");
    [eve deliverTo:efg];
    sqlRun(eve, @"DELETE FROM outbox");   // Fred's Kopie gilt als zugestellt
    [eve.messenger maintainGroups];
    check(eve.outbox.count == 1 && opened(eve.outbox[0], fred, eve).type == MeshEnvelopeGroupLeave, "unlock: deferred gl sent once its predecessor left the queue");
    [eve deliverTo:efg]; [fred deliverTo:efg];
    check(statusOf(gina, g2) == MeshGroupMember && [stateOf(gina, g2).admin isEqualToString:fred.pubkey] && ![stateOf(gina, g2) hasMember:eve.pubkey]
          && ![stateOf(fred, g2) hasMember:eve.pubkey], "transfer+leave: group lives on, new admin removed the old one");

    // Reihenfolge vertauscht: gl vor der Übergabe (bei Mitglied und neuem Admin) -> normaler Austritt
    NSString *g3 = joinGroup(eve, @[fred, gina], efg);
    [eve.messenger transferAdmin:fred.pubkey group:g3 leave:YES];
    NSArray *gsEvents = [eve.outbox copy];
    [eve.outbox removeAllObjects];
    for (MeshEvent *e in gsEvents) [eve.messenger eventStored:e.eventId];
    NSArray *glEvents = [eve.outbox copy];
    [eve.outbox setArray:glEvents];
    [eve deliverTo:efg];   // erst gl
    check(statusOf(gina, g3) == MeshGroupMember && statusOf(fred, g3) == MeshGroupMember, "gl of the admin before the transfer: held, not dissolved");
    [eve.outbox setArray:gsEvents];
    [eve deliverTo:efg];   // dann die Übergabe
    [fred deliverTo:efg];
    check(statusOf(gina, g3) == MeshGroupMember && [stateOf(gina, g3).admin isEqualToString:fred.pubkey] && ![stateOf(gina, g3) hasMember:eve.pubkey]
          && ![stateOf(fred, g3) hasMember:eve.pubkey], "held gl became a normal leave after the transfer");
    check(![[fred.messenger valueForKey:@"heldGroupControl"] count] && [fred.messenger secondsUntilNextExpiry] < 0, "nothing held any more");

    // Zustand des neuen Admins vor der Übergabe: wartet und gilt danach
    NSString *g4 = joinGroup(eve, @[fred, gina], efg);
    [eve.messenger transferAdmin:fred.pubkey group:g4 leave:NO];
    deliverOnly(eve, fred);
    [fred.messenger renameGroup:g4 to:@"Später"];
    deliverOnly(fred, gina);
    check([stateOf(gina, g4).admin isEqualToString:eve.pubkey] && ![stateOf(gina, g4).name isEqualToString:@"Später"], "new admin's state before the transfer: held");
    deliverOnly(eve, gina);
    check([stateOf(gina, g4).admin isEqualToString:fred.pubkey] && [stateOf(gina, g4).name isEqualToString:@"Später"], "held state applied after the transfer");
    // Wer vor der Übergabe ging, hat noch den alten Admin: Einladung des neuen abgelehnt (B1)
    NSString *g5 = joinGroup(eve, @[fred, gina], efg);
    [gina.messenger leaveGroup:g5];
    [gina deliverTo:efg]; [eve deliverTo:efg];
    [eve.messenger transferAdmin:fred.pubkey group:g5 leave:NO];
    [eve deliverTo:efg];
    [fred befriend:gina]; [gina befriend:fred];
    check([fred.messenger invite:@[gina.pubkey] toGroup:g5], "new admin re-invites who left before");
    [fred deliverTo:efg];
    check(statusOf(gina, g5) == MeshGroupLeft && [stateOf(gina, g5).admin isEqualToString:eve.pubkey], "who left before the transfer rejects the new admin's invitation");
    // Wartendes verfällt nach 15 min
    MeshEvent *early = dmFrom(eve, gina, [MeshEnvelope groupState:[[[stateOf(fred, g4) renamed:@"X"] withAdmin:eve.pubkey] json]]);
    [gina.messenger receive:early];
    NSMutableDictionary *held = [gina.messenger valueForKey:@"heldGroupControl"][g4];
    check(held[@"state"] != nil, "state of a member claiming admin held");
    held[@"stateAt"] = @(MeshNow() - 16 * 60);
    [gina.messenger deleteExpired];
    check(![[gina.messenger valueForKey:@"heldGroupControl"] count], "held state dropped after 15 min");
}

static void testB9Proposals(void) {
    Device *anna = [[Device alloc] initNamed:@"pranna"], *ben = [[Device alloc] initNamed:@"prben"], *cleo = [[Device alloc] initNamed:@"prcleo"],
           *dora = [[Device alloc] initNamed:@"prdora"];
    NSArray *all = @[anna, ben, cleo, dora];
    NSString *gid = joinGroup(anna, @[ben], all);
    [ben befriend:cleo]; [cleo befriend:ben];   // Cleo kennt Anna nicht und umgekehrt
    check(![ben.messenger proposeContact:dora.pubkey name:@"Dora" group:gid], "only own accepted contacts can be proposed");
    check(![anna.messenger proposeContact:cleo.pubkey name:@"Carol" group:gid], "admin doesn't propose (invites directly)");
    check([ben.messenger proposeContact:cleo.pubkey name:@"Carol" group:gid], "B9 ben proposes cleo");
    check(lastNotice(ben, gid).groupNotice == MeshGroupNoticeProposed && [lastNotice(ben, gid).text isEqualToString:@"Carol"], "\"You proposed Carol\"");
    MeshEnvelope *gvo = nil, *gpr = nil;
    for (MeshEvent *e in ben.outbox) {
        if ([e hasTag:@"p" value:cleo.pubkey]) gvo = opened(e, cleo, ben);
        if ([e hasTag:@"p" value:anna.pubkey]) gpr = opened(e, anna, ben);
    }
    check(gvo.type == MeshEnvelopeGroupVouch && [gvo.subject isEqualToString:anna.pubkey] && [gvo.subjectName isEqualToString:@"B8"]
          && gpr.type == MeshEnvelopeGroupPropose && [gpr.subject isEqualToString:cleo.pubkey], "gvo to cleo, gpr to the admin");
    [ben deliverTo:all];
    NSArray *props = [anna.messenger proposalsForGroup:gid];
    check(props.count == 1 && [props[0][@"from"] isEqualToString:ben.pubkey] && [props[0][@"name"] isEqualToString:@"Carol"], "admin sees the proposal");
    check(sqlInt(anna, @"SELECT COUNT(*) FROM group_records WHERE instr(data,'Carol')>0 OR substr(data,1,5)!='enc2:'") == 0
          && sqlInt(cleo, @"SELECT COUNT(*) FROM group_records WHERE kind=4 AND substr(data,1,5)='enc2:'") == 1, "proposal and voucher sealed");
    check([cleo.messenger voucherFor:gid admin:anna.pubkey] && [[cleo.messenger voucherFor:gid admin:anna.pubkey] isEqualToString:ben.pubkey], "cleo holds ben's voucher");
    // Regeln beim Admin
    NSString *gprAgain = [MeshEnvelope groupPropose:gid candidate:cleo.pubkey name:@"Cleo"];
    [anna.messenger receive:dmFrom(ben, anna, gprAgain)];
    check([anna.messenger proposalsForGroup:gid].count == 1 && [[anna.messenger proposalsForGroup:gid][0][@"name"] isEqualToString:@"Carol"], "one proposal per (gid, C), later ignored");
    check(![anna.messenger receive:dmFrom(dora, anna, [MeshEnvelope groupPropose:gid candidate:A64('1') name:@"X"])], "gpr from a non-member rejected");
    check(![anna.messenger receive:dmFrom(ben, anna, [MeshEnvelope groupPropose:gid candidate:A64('2') name:[@"" stringByPaddingToLength:41 withString:@"x" startingAtIndex:0]])], "gpr name > 40 rejected");
    check(![anna.messenger receive:dmFrom(ben, anna, [MeshEnvelope groupPropose:gid candidate:anna.pubkey name:@"Ich"])], "gpr for the admin himself rejected");
    check(![anna.messenger receive:dmFrom(ben, anna, [MeshEnvelope groupPropose:gid candidate:ben.pubkey name:@"Ben"])], "gpr for a member rejected");
    [anna.store blockContact:A64('3')];
    check(![anna.messenger receive:dmFrom(ben, anna, [MeshEnvelope groupPropose:gid candidate:A64('3') name:@"B"])], "gpr for a blocked key rejected");
    check([anna.messenger receive:dmFrom(ben, anna, [MeshEnvelope groupPropose:gid candidate:A64('4') name:@""])], "gpr with empty name allowed");
    for (int i = 0; i < 4; i++) [anna.messenger receive:dmFrom(ben, anna, [MeshEnvelope groupPropose:gid candidate:A64('5' + i) name:@"n"])];
    check([anna.messenger proposalsForGroup:gid].count == 5, "at most 5 per proposer");
    // höchstens 20 je Gruppe
    NSMutableArray *more = [NSMutableArray array];
    for (int i = 0; i < 4; i++) [more addObject:[[Device alloc] initNamed:[NSString stringWithFormat:@"prm%d", i]]];
    NSString *g2 = joinGroup(anna, more, [more arrayByAddingObject:anna]);
    int n = 0;
    for (Device *m in more) for (int i = 0; i < 5; i++) n += [anna.messenger receive:dmFrom(m, anna, [MeshEnvelope groupPropose:g2 candidate:[NSString stringWithFormat:@"%062x%02x", (unsigned)(m.hash & 0xffff), i] name:@"x"])] ? 1 : 0;
    Device *fifth = [[Device alloc] initNamed:@"prm5"];
    [anna befriend:fifth]; [fifth befriend:anna];
    [anna.messenger invite:@[fifth.pubkey] toGroup:g2]; [anna deliverTo:@[fifth]];
    [fifth.messenger acceptInvite:g2 myName:@"F"]; [fifth deliverTo:@[anna]]; [anna deliverTo:[more arrayByAddingObject:fifth]];
    check(n == 20 && ![anna.messenger receive:dmFrom(fifth, anna, [MeshEnvelope groupPropose:g2 candidate:A64('e') name:@"x"])], "at most 20 per group");
    // 30 Tage
    sqlRun(anna, [NSString stringWithFormat:@"UPDATE group_records SET at=%lld WHERE kind=3 AND gid='%@'", MeshNow() - 31 * 24 * 3600, g2]);
    [anna.messenger maintainGroups];
    check(![anna.messenger proposalsForGroup:g2].count, "proposals forgotten after 30 days");

    // Einladen: C ist kein Kontakt des Admins, sieht die Einladung dank Bürgschaft
    NSNumber *pid = [anna.messenger proposalsForGroup:gid][0][@"id"];
    check([anna.messenger acceptProposal:pid.longLongValue group:gid] && [[anna.messenger pendingInvitesForGroup:gid] containsObject:cleo.pubkey], "admin invites the proposed contact");
    check(![anna.messenger proposalsForGroup:gid].count || ![[[anna.messenger proposalsForGroup:gid] valueForKey:@"candidate"] containsObject:cleo.pubkey], "proposal done");
    [anna deliverTo:all];
    check(statusOf(cleo, gid) == MeshGroupInvited && [[cleo.messenger voucherForInvite:gid] isEqualToString:ben.pubkey], "B9 vouched invitation shown (admin unknown)");
    // Bürge nicht mehr angenommen: Bürgschaft gilt nicht (Anzeigen und Annehmen)
    sqlRun(cleo, [NSString stringWithFormat:@"UPDATE contacts SET accepted=0 WHERE pubkey='%@'", ben.pubkey]);
    check(![cleo.messenger voucherForInvite:gid] && ![cleo.messenger acceptInvite:gid myName:@"Cleo"], "voucher only while the voucher is an accepted contact");
    sqlRun(cleo, [NSString stringWithFormat:@"UPDATE contacts SET accepted=1 WHERE pubkey='%@'", ben.pubkey]);
    check([cleo.messenger acceptInvite:gid myName:@"Cleo"], "vouched invitation joined");
    [cleo deliverTo:all]; [anna deliverTo:all];
    check(statusOf(cleo, gid) == MeshGroupMember && ![cleo.messenger voucherFor:gid admin:anna.pubkey], "member, voucher used up");
    // Ablehnen = still
    [anna.messenger receive:dmFrom(ben, anna, [MeshEnvelope groupPropose:gid candidate:A64('9') name:@"Z"])];
    NSDictionary *z = nil;
    for (NSDictionary *p in [anna.messenger proposalsForGroup:gid]) if ([p[@"candidate"] isEqualToString:A64('9')]) z = p;
    int before = (int)anna.outbox.count;
    check(z && [anna.messenger rejectProposal:[z[@"id"] longLongValue] group:gid] && (int)anna.outbox.count == before, "reject: silent");

    // Ohne Bürgschaft gilt B8.5; gvo nur von angenommenen Kontakten; gvo nach gi zeigt sofort
    Device *eve = [[Device alloc] initNamed:@"preve"];
    MeshGroupState *st = [MeshGroupState stateWithGroup:@"abababababababab" name:@"Fremd" admin:dora.pubkey adminName:@"Dora"];
    MeshEvent *gi = dmFrom(dora, eve, [MeshEnvelope groupInvite:[st json]]);
    [eve.messenger receive:gi];
    check(statusOf(eve, @"abababababababab") == (MeshGroupStatus)-1 && [eve.store heldInviteCount] == 1, "no voucher: held (B8.5)");
    check(![eve.messenger receive:dmFrom(ben, eve, [MeshEnvelope groupVouch:@"abababababababab" admin:dora.pubkey groupName:@"Fremd"])]
          && ![eve.messenger voucherFor:@"abababababababab" admin:dora.pubkey], "gvo from a non-contact rejected");
    [eve befriend:ben];
    check(![eve.messenger receive:dmFrom(ben, eve, [MeshEnvelope groupVouch:@"abababababababab" admin:ben.pubkey groupName:@"Fremd"])], "gvo with admin = voucher rejected");
    check(![eve.messenger receive:dmFrom(ben, eve, [MeshEnvelope groupVouch:@"abababababababab" admin:eve.pubkey groupName:@"Fremd"])], "gvo with admin = me rejected");
    check([eve.messenger receive:dmFrom(ben, eve, [MeshEnvelope groupVouch:@"abababababababab" admin:dora.pubkey groupName:@"Fremd"])]
          && statusOf(eve, @"abababababababab") == MeshGroupInvited && ![eve.store heldInviteCount], "gvo after gi: held invitation shown at once");
    check(![eve.messenger voucherFor:@"abababababababab" admin:cleo.pubkey], "voucher only for exactly this admin");
    // höchstens 5 je Bürge, 20 insgesamt (die älteste fällt heraus), 30 Tage
    for (int i = 0; i < 6; i++) [eve.messenger receive:dmFrom(ben, eve, [MeshEnvelope groupVouch:[NSString stringWithFormat:@"%016x", 0x500 + i] admin:dora.pubkey groupName:@"x"])];
    check(sqlInt(eve, @"SELECT COUNT(*) FROM group_records WHERE kind=4") == 5, "at most 5 vouchers per voucher");
    for (int v = 0; v < 4; v++) {
        Device *w = [[Device alloc] initNamed:[NSString stringWithFormat:@"prv%d", v]];
        [eve befriend:w];
        for (int i = 0; i < 5; i++) [eve.messenger receive:dmFrom(w, eve, [MeshEnvelope groupVouch:[NSString stringWithFormat:@"%016x", 0x600 + v * 8 + i] admin:dora.pubkey groupName:@"x"])];
    }
    check(sqlInt(eve, @"SELECT COUNT(*) FROM group_records WHERE kind=4") == 20, "at most 20 vouchers, oldest drop out");
    sqlRun(eve, [NSString stringWithFormat:@"UPDATE group_records SET at=%lld WHERE kind=4", MeshNow() - 31 * 24 * 3600]);
    [eve.messenger maintainGroups];
    check(sqlInt(eve, @"SELECT COUNT(*) FROM group_records WHERE kind=4") == 0, "vouchers forgotten after 30 days");
}

static void testB10Open(void) {
    Device *anna = [[Device alloc] initNamed:@"b10anna"], *ben = [[Device alloc] initNamed:@"b10ben"], *dora = [[Device alloc] initNamed:@"b10dora"],
           *eve = [[Device alloc] initNamed:@"b10eve"];
    NSArray *all = @[anna, ben, dora, eve];
    NSString *gid = joinGroup(anna, @[ben], all);
    check(![anna.messenger groupLink:gid] && ![ben.messenger setGroupOpen:YES group:gid], "closed: no link; only the admin opens");
    long long r0 = stateOf(anna, gid).revision;
    check([anna.messenger setGroupOpen:YES group:gid] && stateOf(anna, gid).open && stateOf(anna, gid).revision == r0 + 1, "B10 open: r+1 with o");
    NSString *link = [anna.messenger groupLink:gid];
    MeshGroupLink *l = [MeshGroupLink parse:link];
    check(l && [l.gid isEqualToString:gid] && [l.admin isEqualToString:anna.pubkey], "admin link");
    check(sqlInt(anna, [NSString stringWithFormat:@"SELECT COUNT(*) FROM groups WHERE instr(lkey,'%@')>0 OR substr(lkey,1,5)!='enc2:'", l.key]) == 0, "k sealed");
    check([stateOf(anna, gid).json rangeOfString:l.key].location == NSNotFound, "k never in the state");
    [anna deliverTo:all];
    check(stateOf(ben, gid).open && [[ben.messenger groupLink:gid] isEqualToString:link] && lastNotice(ben, gid).groupNotice == MeshGroupNoticeOpened, "member got o, gk and \"open\" notice");

    // Beitritt per Link (Dora ist kein Kontakt)
    NSString *joined = [dora.messenger joinGroupByLink:link name:@"Karte" myName:@"Dora"];
    check([joined isEqualToString:gid] && statusOf(dora, gid) == MeshGroupLinkJoining && [stateOf(dora, gid).name isEqualToString:@"Karte"]
          && stateOf(dora, gid).revision == 0 && [stateOf(dora, gid).members isEqualToArray:@[anna.pubkey]], "joiner: placeholder (r=0, m=[admin])");
    MeshEnvelope *gj = opened(dora.outbox.lastObject, anna, dora);
    check(gj.type == MeshEnvelopeGroupJoin && [gj.joinKey isEqualToString:l.key] && [gj.joinName isEqualToString:@"Dora"], "gj with k to the admin");
    // vorher: Zustand ohne mich bzw. von jemand anderem nicht übernehmen
    check(![dora.messenger receive:dmFrom(anna, dora, [MeshEnvelope groupState:[[stateOf(anna, gid) bumped] json]])] && statusOf(dora, gid) == MeshGroupLinkJoining,
          "joiner: state without me not taken");
    MeshGroupState *fakeWithMe = [[MeshGroupState stateWithGroup:gid name:@"Fake" admin:ben.pubkey adminName:@""] withMember:dora.pubkey name:@"D"];
    check(![dora.messenger receive:dmFrom(ben, dora, [MeshEnvelope groupState:[fakeWithMe json]])] && statusOf(dora, gid) == MeshGroupLinkJoining,
          "joiner: state from someone other than the link admin not taken");
    [dora deliverTo:all];
    check([stateOf(anna, gid) hasMember:dora.pubkey], "B10 admin accepts gj with k");
    [anna deliverTo:all];
    check(statusOf(dora, gid) == MeshGroupMember && [stateOf(dora, gid).name isEqualToString:@"B8"] && [[dora.messenger groupLink:gid] isEqualToString:link],
          "joiner member, got the state and k");
    check([stateOf(ben, gid) hasMember:dora.pubkey], "others got the new state");

    // Ablehnen: falsches k, gesperrt, kürzlich entfernt, Rate, voll, geschlossen
    NSString *wrong = [MeshEnvelope groupJoin:gid name:@"Eve" key:@"ffffffffffffffffffffffffffffffff"];
    check(![anna.messenger receive:dmFrom(eve, anna, wrong)] && ![stateOf(anna, gid) hasMember:eve.pubkey], "wrong k rejected");
    check(![anna.messenger receive:dmFrom(eve, anna, [MeshEnvelope groupJoin:gid name:@"Eve"])], "gj without k and without invitation rejected");
    [anna.store blockContact:eve.pubkey];
    check(![anna.messenger receive:dmFrom(eve, anna, [MeshEnvelope groupJoin:gid name:@"Eve" key:l.key])], "blocked rejected");
    [anna.store unblockContact:eve.pubkey];
    check([anna.messenger removeMember:dora.pubkey fromGroup:gid], "admin removes dora");
    check(![anna.messenger receive:dmFrom(dora, anna, [MeshEnvelope groupJoin:gid name:@"Dora" key:l.key])], "removed in the last 24 h rejected");
    sqlRun(anna, [NSString stringWithFormat:@"UPDATE group_records SET at=%lld WHERE kind=2", MeshNow() - 25 * 3600]);
    check([anna.messenger receive:dmFrom(dora, anna, [MeshEnvelope groupJoin:gid name:@"Dora" key:l.key])], "after 24 h accepted again");
    for (int i = 0; i < 10; i++) sqlRun(anna, [NSString stringWithFormat:@"INSERT INTO group_records(kind,gid,at,data) VALUES(1,'%@',%lld,'x')", gid, MeshNow()]);
    check(![anna.messenger receive:dmFrom(eve, anna, [MeshEnvelope groupJoin:gid name:@"Eve" key:l.key])], "more than 10 link joins per hour rejected");
    sqlRun(anna, @"DELETE FROM group_records WHERE kind=1");
    // Einladung zählt vor k: wer eingeladen ist, tritt normal bei (auch mit falschem k)
    [anna befriend:eve];
    [anna.messenger invite:@[eve.pubkey] toGroup:gid];
    check([anna.messenger receive:dmFrom(eve, anna, wrong)] && [stateOf(anna, gid) hasMember:eve.pubkey], "gj with k from an invitee = normal join");
    // voll (< 20 zählt nur Mitglieder)
    MeshGroupState *big = stateOf(anna, gid);
    for (int i = 0; big.members.count < 20; i++) big = [big withMember:[NSString stringWithFormat:@"%062x%02x", 0x77, i] name:@"x"];
    [anna.store saveGroup:gid state:[big json] status:MeshGroupMember inviter:nil];
    Device *fred = [[Device alloc] initNamed:@"b10fred"];
    check(![anna.messenger receive:dmFrom(fred, anna, [MeshEnvelope groupJoin:gid name:@"Fred" key:l.key])], "full group rejects link joins");

    // Link zurücksetzen und schließen
    NSString *g2 = joinGroup(anna, @[ben], all);
    [anna.messenger setGroupOpen:YES group:g2];
    NSString *k1 = [MeshGroupLink parse:[anna.messenger groupLink:g2]].key;
    check([anna.messenger resetGroupLink:g2], "reset link");
    NSString *k2 = [MeshGroupLink parse:[anna.messenger groupLink:g2]].key;
    check(k2 && ![k1 isEqualToString:k2] && stateOf(anna, g2).open, "new k, still open");
    check(![anna.messenger receive:dmFrom(fred, anna, [MeshEnvelope groupJoin:g2 name:@"Fred" key:k1])], "old link no longer works");
    [anna deliverTo:all];
    check([[MeshGroupLink parse:[ben.messenger groupLink:g2]].key isEqualToString:k2], "members got the new k");
    check([anna.messenger setGroupOpen:NO group:g2] && !stateOf(anna, g2).open && ![anna.messenger groupLink:g2], "closed: no o, no k");
    [anna deliverTo:all];
    check(![ben.messenger groupLink:g2] && ![ben.store groupLinkKey:g2] && lastNotice(ben, g2).groupNotice == MeshGroupNoticeClosed, "member: k deleted, \"no longer open\"");
    check(![anna.messenger receive:dmFrom(fred, anna, [MeshEnvelope groupJoin:g2 name:@"Fred" key:k2])], "closed group rejects link joins");

    // gk-Regeln
    [anna.messenger setGroupOpen:YES group:g2];
    NSArray *open2 = [anna.outbox copy];
    [anna.outbox removeAllObjects];
    MeshEvent *gkEvent = nil, *gsEvent = nil;
    for (MeshEvent *e in open2) if ([e hasTag:@"p" value:ben.pubkey]) {
        MeshEnvelope *env = opened(e, ben, anna);
        if (env.type == MeshEnvelopeGroupKey) gkEvent = e;
        if (env.type == MeshEnvelopeGroupState) gsEvent = e;
    }
    check(![ben.messenger receive:dmFrom(dora, ben, [MeshEnvelope groupKey:g2 key:@"0123456789abcdef0123456789abcdef"])] && ![ben.store groupLinkKey:g2], "gk from a non-member ignored");
    check(![ben.messenger receive:gkEvent] && ![ben.store groupLinkKey:g2] && ![ben.store isDeleted:gkEvent.eventId], "gk before the open state: held, not stored");
    [ben.messenger receive:gsEvent];
    check([ben.store groupLinkKey:g2].length == 32, "held gk applied once the state is open");
    NSString *g2k = [ben.store groupLinkKey:g2];
    check(![ben.messenger receive:dmFrom(fred, ben, [MeshEnvelope groupKey:g2 key:@"00000000000000000000000000000000"])]
          && [[ben.store groupLinkKey:g2] isEqualToString:g2k], "gk from a non-admin doesn't replace k");

    // Übergabe schließt die Gruppe; k reist nicht mit
    [anna.messenger transferAdmin:ben.pubkey group:g2 leave:NO];
    check(!stateOf(anna, g2).open && ![anna.store groupLinkKey:g2] && ![anna.messenger groupLink:g2], "transfer closes; old admin forgets k");
    [anna deliverTo:all];
    check(!stateOf(ben, g2).open && ![ben.store groupLinkKey:g2] && ![ben.messenger groupLink:g2], "new admin has no k (can open again)");
    check(![ben.messenger receive:dmFrom(fred, ben, [MeshEnvelope groupJoin:g2 name:@"Fred" key:g2k])]
          && ![anna.messenger receive:dmFrom(fred, anna, [MeshEnvelope groupJoin:g2 name:@"Fred" key:g2k])], "old link fails at both");
    check(![ben.messenger receive:dmFrom(anna, ben, [MeshEnvelope groupKey:g2 key:g2k])] && ![ben.store groupLinkKey:g2], "gk from the old admin ignored");
    check([ben.messenger setGroupOpen:YES group:g2] && [ben.messenger groupLink:g2], "new admin opens again");

    // 7 Tage ohne Zustand: Beitritt fehlgeschlagen; anderer Admin / aufgelöst: Link-Beitritt abgelehnt
    Device *gina = [[Device alloc] initNamed:@"b10gina"];
    NSString *g3link = [ben.messenger groupLink:g2];
    check([[gina.messenger joinGroupByLink:g3link name:@"" myName:@"Gina"] isEqualToString:g2] && [stateOf(gina, g2).name isEqualToString:@"Group"], "join (name fallback)");
    sqlRun(gina, [NSString stringWithFormat:@"UPDATE groups SET link_at=%lld", MeshNow() - 8 * 24 * 3600]);
    [gina.messenger maintainGroups];
    check(statusOf(gina, g2) == MeshGroupJoinFailed, "B10 after 7 days: join failed");
    [gina.outbox removeAllObjects];
    check([[gina.messenger joinGroupByLink:g3link name:@"" myName:@"Gina"] isEqualToString:g2] && statusOf(gina, g2) == MeshGroupLinkJoining, "failed entry with the same admin reused");
    NSString *otherAdmin = [MeshGroupLink linkWithGroup:g2 admin:A64('d') key:@"00112233445566778899aabbccddeeff"];
    check(![gina.messenger joinGroupByLink:otherAdmin name:@"" myName:@"Gina"], "same gid, other admin: rejected");
    check(![gina.messenger joinGroupByLink:[MeshGroupLink linkWithGroup:@"1212121212121212" admin:gina.pubkey key:@"00112233445566778899aabbccddeeff"] name:@"" myName:@""], "own link rejected");
    [gina deliverTo:all]; [ben deliverTo:[all arrayByAddingObject:gina]];
    check(statusOf(gina, g2) == MeshGroupMember, "rejoined via link");
    [ben.messenger leaveGroup:g2];
    [ben deliverTo:[all arrayByAddingObject:gina]];
    check(statusOf(gina, g2) == MeshGroupDissolved && ![gina.messenger joinGroupByLink:g3link name:@"" myName:@"Gina"], "dissolved: link join rejected");

    // Link-Karte im 1:1-Chat; in Gruppen gesperrt; ungültige verworfen
    [eve befriend:anna]; [anna befriend:eve];
    NSString *card = [MeshPayload contentWithGroupLinkName:@"Club" link:link];
    check([anna.messenger send:card to:eve.pubkey replyTo:nil] != nil, "glink card sent 1:1");
    [anna deliverTo:all];
    MeshMessage *got = [eve.store messagesForChat:anna.pubkey].lastObject;
    check(got.kind == MeshPayloadGroupLink && [[MeshPayload parse:got.content].code isEqualToString:link], "glink card received 1:1");
    check(![anna.messenger sendGroup:gid content:card replyTo:nil], "glink card not sent in groups");
    MeshEvent *inGroup = groupMsg(ben, anna, gid, card, @"7b7b7b7b7b7b7b7b");
    check(![anna.messenger receive:inGroup] && [anna.store isDeleted:inGroup.eventId], "glink card in a group discarded");
    NSString *broken = @"\1mesh:glink:VGVzdA==\nmeshg:1:xyz";
    MeshEvent *bad = dmFrom(anna, eve, [MeshEnvelope message:broken cmid:@"6c6c6c6c6c6c6c6c" replyTo:nil timer:0 mode:MeshTimerFromRead bundle:nil]);
    check(![eve.messenger receive:bad] && [eve.store isDeleted:bad.eventId], "invalid glink card discarded");
}

int main(void) {
    @autoreleasepool {
        testVectors();
        testGroups();
        testPictureVectors();
        testGroupPicture();
        testTeam();
        testIsolatedPool();
        testB8();
        testFanout();
        testB9B10Vectors();
        testB9Transfer();
        testB9Proposals();
        testB10Open();
    }
    return testsDone();
}
