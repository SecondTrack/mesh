// Zwei MeshMessenger tauschen Events direkt aus (ohne Relays): Nachrichten mit ID, Antworten,
// Reaktionen, Löschen für alle, Chat leeren, Selbstlöschen, Wiederholungen und Fremde.
#import "MeshTest.h"
#import "MeshMessenger.h"
#import "MeshStore.h"
#import "MeshStore+Chat.h"
#import "MeshInboxPolicy.h"
#import "MeshKeys.h"
#import "MeshEvent.h"
#import "MeshMessage.h"
#import "MeshPayload.h"
#import "MeshEnvelope.h"
#import "MeshProfile.h"
#import "MeshBase64.h"
#import "MeshNip04.h"
#import "MeshNip44.h"
#import "MeshHex.h"
#import "MeshPanic.h"
#import "MeshSignal.h"
#import "MeshStore+Signal.h"

// Ein Gerät: Store auf einer temporären Datei, gesendete Events landen in outbox.
@interface Device : NSObject <MeshMessengerDelegate>
@property (nonatomic) MeshStore *store;
@property (nonatomic) MeshMessenger *messenger;
@property (nonatomic) MeshKeys *keys;
@property (nonatomic) NSMutableArray *outbox;
@property (nonatomic, readonly) NSString *pubkey;
@property (nonatomic) MeshPanic *panic;
@property (nonatomic) int wipes;
@property (nonatomic) int pictureChanges;
@end

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

@implementation Device
- (instancetype)initNamed:(NSString *)name signal:(BOOL)withSignal {
    if ((self = [super init])) {
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"mesh-messenger-%@-%d.sqlite", name, getpid()]];
        [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
        [[NSFileManager defaultManager] removeItemAtPath:[path stringByAppendingString:@"-journal"] error:NULL];
        _store = [MeshStore new];
        [_store openAtPath:path];
        NSMutableData *key = [NSMutableData dataWithLength:32]; arc4random_buf(key.mutableBytes, 32);
        [_store setDataKey:key];
        _keys = [MeshKeys generate];
        _panic = [[MeshPanic alloc] initWithStorage:[MemoryPanicStorage new]];
        _messenger = [[MeshMessenger alloc] initWithStore:_store keys:_keys inbox:[[MeshInboxPolicy alloc] initWithStore:_store] panic:_panic];
        _messenger.delegate = self;
        if (withSignal) _messenger.signal = [[MeshSignal alloc] initWithStorage:_store seed:_keys.seckey];
        _outbox = [NSMutableArray array];
    }
    return self;
}
- (NSString *)pubkey { return [MeshHex encode:_keys.xonlyPub]; }
- (void)messenger:(MeshMessenger *)m send:(MeshEvent *)event { [_outbox addObject:event]; }
- (void)messenger:(MeshMessenger *)m acceptedContact:(NSString *)peer {}
- (void)messengerReceivedPanic:(MeshMessenger *)m { _wipes++; }
- (void)messenger:(MeshMessenger *)m received:(MeshMessage *)message from:(NSString *)peer {}
- (void)messenger:(MeshMessenger *)m changedPictureOf:(NSString *)peer { _pictureChanges++; }
// Alles Gesendete beim anderen zustellen.
- (int)deliverTo:(Device *)other {
    int changed = 0;
    for (MeshEvent *e in _outbox) changed += [other.messenger receive:e] ? 1 : 0;
    [_outbox removeAllObjects];
    return changed;
}
- (NSArray *)chatWith:(Device *)other { return [_store messagesForChat:other.pubkey]; }
@end

static void testConversation(Device *a, Device *b) {
    [a.store upsertContact:b.pubkey name:@"Bob" accepted:YES];
    MeshMessage *sent = [a.messenger send:@"Hallo Bob" to:b.pubkey replyTo:nil];
    check(sent.cmid.length == 16 && sent.eventId.length == 64, "sent with cmid");
    MeshEvent *wire = a.outbox.firstObject;
    check([wire hasTag:@"p" value:b.pubkey] && [wire.content rangeOfString:@"?iv="].location == NSNotFound, "NIP-44 on the wire");
    check([a deliverTo:b] == 1, "bob receives");
    MeshMessage *got = [b chatWith:a].firstObject;
    check([got.content isEqualToString:@"Hallo Bob"] && [got.cmid isEqualToString:sent.cmid] && !got.fromMe, "same text and cmid");
    check(![b.store isAccepted:a.pubkey], "first contact is a request");

    MeshMessage *reply = [b.messenger send:@"Hi Alice" to:a.pubkey replyTo:got.cmid];
    check([b.store isAccepted:a.pubkey], "replying accepts");
    [b deliverTo:a];
    MeshMessage *quoted = [a.store messageWithKey:reply.cmid chat:b.pubkey];
    check([quoted.replyTo isEqualToString:sent.cmid], "reply points to the quoted message");

    // Wiederholung desselben Events (zweites Relay) ändert nichts
    [b.messenger send:@"doppelt" to:a.pubkey replyTo:nil];
    MeshEvent *again = b.outbox.firstObject;
    [b deliverTo:a];
    check(![a.messenger receive:again] && [a chatWith:b].count == 3, "duplicate ignored");
}

static void testReactions(Device *a, Device *b) {
    MeshMessage *target = [a chatWith:b].firstObject;   // Alices "Hallo Bob"
    MeshMessage *atBob = [b.store messageWithKey:target.cmid chat:a.pubkey];
    check([b.messenger react:@"👍" to:atBob in:a.pubkey], "bob reacts");
    check([b deliverTo:a] == 1, "reaction arrives");
    check([[a.store messageWithKey:target.cmid chat:b.pubkey].reactPeer isEqualToString:@"👍"], "alice sees reaction");
    check([a chatWith:b].count == 3, "reaction is no message");

    atBob = [b.store messageWithKey:target.cmid chat:a.pubkey];
    [b.messenger react:@"👍" to:atBob in:a.pubkey];   // gleiche Reaktion = entfernen
    [b deliverTo:a];
    check(![a.store messageWithKey:target.cmid chat:b.pubkey].reactPeer, "reaction toggled off");
}

static void testDelete(Device *a, Device *b) {
    MeshMessage *oops = [a.messenger send:@"falscher Chat" to:b.pubkey replyTo:nil];
    [a deliverTo:b];
    check([b.store messageWithKey:oops.cmid chat:a.pubkey] != nil, "arrived");
    check([a.messenger deleteForEveryone:oops in:b.pubkey], "delete for everyone");
    [a deliverTo:b];
    check(![b.store messageWithKey:oops.cmid chat:a.pubkey] && ![a.store messageWithKey:oops.cmid chat:b.pubkey], "gone on both sides");

    MeshMessage *bobs = [b.messenger send:@"meins" to:a.pubkey replyTo:nil];
    [b deliverTo:a];
    MeshMessage *atAlice = [a.store messageWithKey:bobs.cmid chat:b.pubkey];
    check(![a.messenger deleteForEveryone:atAlice in:b.pubkey], "cannot delete the other's message for everyone");
    // Selbst gebaute Anweisung, Bobs Nachricht bei Bob zu löschen: wird ignoriert
    NSString *forged = [MeshEnvelope deletionOf:bobs.cmid];
    MeshEvent *e = [MeshEvent kind:4 content:[MeshNip44 encrypt:forged keys:a.keys peerXonlyPub:b.keys.xonlyPub] tags:@[@[@"p", b.pubkey]]];
    [e signWithKeys:a.keys];
    [b.messenger receive:e];
    check([b.store messageWithKey:bobs.cmid chat:a.pubkey] != nil, "own message survives forged delete");
}

static void testTimer(Device *a, Device *b) {
    [a.messenger setTimer:30 fromSent:NO for:b.pubkey];
    check([a deliverTo:b] == 1, "timer arrives");
    BOOL sent = YES;
    check([b.messenger timerFor:a.pubkey fromSent:&sent] == 30 && !sent, "timer mirrored");
    MeshMessage *note = [b chatWith:a].lastObject;
    check(note.kind == MeshPayloadNotice && !note.fromMe && [MeshPayload parseNotice:note.content].seconds == 30, "notice line");

    MeshMessage *m = [a.messenger send:@"verschwindet" to:b.pubkey replyTo:nil];
    check(m.timer == 30 && m.expiresAt == 0, "from read: no clock yet");
    [a deliverTo:b];
    MeshMessage *atBob = [b.store messageWithKey:m.cmid chat:a.pubkey];
    check(atBob.timer == 30 && atBob.expiresAt == 0, "clock waits for reading");
    [b.messenger chatOpened:a.pubkey];
    atBob = [b.store messageWithKey:m.cmid chat:a.pubkey];
    check(atBob.expiresAt > 0 && [b.messenger secondsUntilNextExpiry] <= 30, "clock starts on open");

    b.messenger.openChat = a.pubkey;
    MeshMessage *live = [a.messenger send:@"gleich gelesen" to:b.pubkey replyTo:nil];
    [a deliverTo:b];
    check([b.store messageWithKey:live.cmid chat:a.pubkey].expiresAt > 0, "open chat starts at once");
    b.messenger.openChat = nil;

    [a.messenger setTimer:10 fromSent:YES for:b.pubkey];
    [a deliverTo:b];
    MeshMessage *fromSent = [a.messenger send:@"ab gesendet" to:b.pubkey replyTo:nil];
    check(fromSent.expiresAt == fromSent.ts + 10, "from sent runs at once");
    [a deliverTo:b];
    check([b.store messageWithKey:fromSent.cmid chat:a.pubkey].expiresAt == fromSent.ts + 10, "receiver uses send time");

    check(![b.messenger deleteExpired], "nothing expired yet");
    check([b.store deleteExpiredAt:time(NULL) + 31] > 0 && ![b.store messageWithKey:m.cmid chat:a.pubkey], "expired message deleted");

    [a.messenger setTimer:0 fromSent:NO for:b.pubkey];
    [a deliverTo:b];
    check([b.messenger timerFor:a.pubkey fromSent:NULL] == 0, "timer off");
}

static void testClear(Device *a, Device *b) {
    [a.messenger send:@"vor dem Leeren" to:b.pubkey replyTo:nil];
    MeshEvent *stale = a.outbox.lastObject;
    [a deliverTo:b];
    [a.messenger clearChat:b.pubkey forEveryone:YES];
    check([a chatWith:b].count == 0, "cleared here");
    [a deliverTo:b];
    check([b chatWith:a].count == 0 && [b.store isContact:a.pubkey], "cleared there, contact stays");
    // Erneut zugestelltes altes Event (anderes Relay) bleibt draußen
    check(![b.messenger receive:stale] && [b chatWith:a].count == 0, "old event stays out");
}

static void testStrangers(Device *a, Device *b) {
    Device *mallory = [[Device alloc] initNamed:@"mallory" signal:NO];
    // Fremde dürfen nichts steuern
    MeshEvent *e = [MeshEvent kind:4 content:[MeshNip44 encrypt:[MeshEnvelope clearChat] keys:mallory.keys peerXonlyPub:b.keys.xonlyPub]
                              tags:@[@[@"p", b.pubkey]]];
    [e signWithKeys:mallory.keys];
    check(![b.messenger receive:e] && ![b.store isContact:mallory.pubkey], "stranger control ignored");

    // Nachricht nicht an mich (fremder p-Tag)
    MeshMessage *notForBob = [mallory.messenger send:@"an alice" to:a.pubkey replyTo:nil];
    check(notForBob && ![b.messenger receive:mallory.outbox.lastObject], "wrong recipient ignored");

    // Alte iPod-Version: NIP-04 ohne Kopf
    NSString *old = [MeshNip04 encrypt:@"mesh:voice:2:AAAA" keys:mallory.keys peerXonlyPub:b.keys.xonlyPub];
    MeshEvent *legacy = [MeshEvent kind:4 content:old tags:@[@[@"p", b.pubkey]]];
    [legacy signWithKeys:mallory.keys];
    check([b.messenger receive:legacy], "NIP-04 still readable");
    MeshMessage *lm = [b.store messagesForChat:mallory.pubkey].lastObject;
    check(lm.kind == MeshPayloadVoice && lm.cmid == nil, "old voice without cmid");
}

static NSString *fakeJpeg(NSUInteger size) {
    NSMutableData *d = [NSMutableData dataWithLength:size];
    arc4random_buf(d.mutableBytes, size);
    memcpy(d.mutableBytes, "\xFF\xD8\xFF\xE0", 4);
    return [MeshBase64 encode:d];
}

static void setOwnPicture(Device *d, NSString *pic) {
    MeshProfile *p = [d.store loadProfile];
    p.picture = pic;
    [d.store saveProfile:p];
}

// Privates Profilbild (\1mesh:pic:) wie Android: nur angenommene Kontakte, geprüft, nie im Chat.
static void testPicture(Device *a, Device *b) {
    NSUInteger before = [b chatWith:a].count;
    NSString *pic = fakeJpeg(3000);
    setOwnPicture(a, pic);
    check([a.messenger sendPictureTo:b.pubkey], "picture sent");
    check([a deliverTo:b] == 0 && [b chatWith:a].count == before, "picture is not a chat message");
    check([[b.store picForContact:a.pubkey] isEqualToString:pic] && b.pictureChanges == 1, "picture stored, ui notified");
    check(b.outbox.count == 0, "no reply without own picture");

    // b hat jetzt ein Bild: auf das nächste Bild von a antwortet b genau einmal
    setOwnPicture(b, fakeJpeg(2000));
    NSString *pic2 = fakeJpeg(2500);
    setOwnPicture(a, pic2);
    [a.messenger sendPictureToAllContacts];
    [a deliverTo:b];
    check([[b.store picForContact:a.pubkey] isEqualToString:pic2], "changed picture replaces old");
    check(b.outbox.count == 1, "one reply with own picture");
    [b deliverTo:a];
    check([[a.store picForContact:b.pubkey] isEqualToString:[b.store loadProfile].picture], "reply stored at a");
    check(a.outbox.count == 1, "a replies once");
    [a deliverTo:b];
    check(b.outbox.count == 0, "no ping-pong");

    // Ungültiges: zu groß, kein JPEG/PNG -> verworfen
    setOwnPicture(a, fakeJpeg(70 * 1024));
    check(![a.messenger sendPictureTo:b.pubkey], "oversized own picture not sent");
    NSString *gif = [MeshBase64 encode:[@"GIF89a-not-allowed" dataUsingEncoding:NSUTF8StringEncoding]];
    MeshEvent *e = [MeshEvent kind:4 content:[MeshNip44 encrypt:[MeshEnvelope picture:gif] keys:a.keys peerXonlyPub:b.keys.xonlyPub]
                              tags:@[@[@"p", b.pubkey]]];
    [e signWithKeys:a.keys];
    check(![b.messenger receive:e] && [[b.store picForContact:a.pubkey] isEqualToString:pic2], "non-image ignored");

    // Fremde: kein Bild, kein Kontakt mit Bild
    Device *mallory = [[Device alloc] initNamed:@"mallory2" signal:NO];
    setOwnPicture(mallory, fakeJpeg(1000));
    [mallory.messenger sendPictureTo:b.pubkey];
    [mallory deliverTo:b];
    check(![b.store picForContact:mallory.pubkey] && b.outbox.count == 0, "stranger picture ignored");

    // Entfernt
    setOwnPicture(a, @"");
    [a.messenger sendPictureToAllContacts];
    [a deliverTo:b];
    check([b.store picForContact:a.pubkey] == nil, "removed picture clears");
    [a.outbox removeAllObjects]; [b.outbox removeAllObjects];
}

static void testLarge(Device *a, Device *b) {
    NSMutableData *big = [NSMutableData dataWithLength:80 * 1024];
    arc4random_buf(big.mutableBytes, big.length);
    MeshMessage *m = [a.messenger send:[MeshPayload contentWithImage:big] to:b.pubkey replyTo:nil];
    MeshEvent *wire = a.outbox.lastObject;
    check(m && [wire.content rangeOfString:@"?iv="].location != NSNotFound, "large media falls back to NIP-04");
    [a deliverTo:b];
    MeshMessage *got = [b.store messageWithKey:m.cmid chat:a.pubkey];
    check(got.kind == MeshPayloadImage && [[[MeshPayload parse:[b.store contentOfMessage:got.rowId]] data] isEqualToData:big], "large image intact");
}

static void testPanic(Device *a, Device *b) {
    check([b.panic setCodeword:@"Leuchtturm" pubkeys:@[b.pubkey]], "codeword set");
    check([a.messenger sendPanicTrigger:@"Falsch" to:b.pubkey], "trigger sent");
    MeshEvent *wrong = a.outbox.lastObject;
    check([wrong.content isEqualToString:@""] && wrong.tags.count == 2, "only p and mw tag, no content");
    [a deliverTo:b];
    check(b.wipes == 0, "wrong codeword does nothing");
    [a.messenger sendPanicTrigger:@" Leuchtturm " to:b.pubkey];
    [a deliverTo:b];
    check(b.wipes == 1, "right codeword wipes");
    [a.messenger send:@"Leuchtturm" to:b.pubkey replyTo:nil];
    [a deliverTo:b];
    check(b.wipes == 2, "codeword as text wipes");
    [a.messenger send:@"Leuchtturm am Meer" to:b.pubkey replyTo:nil];
    [a deliverTo:b];
    check(b.wipes == 2, "other text does not");
}

static void testSignal(void) {
    Device *a = [[Device alloc] initNamed:@"sa" signal:YES], *b = [[Device alloc] initNamed:@"sb" signal:YES];
    [a.store upsertContact:b.pubkey name:@"B" accepted:YES];
    [b.store upsertContact:a.pubkey name:@"A" accepted:YES];
    // Ohne Bundle: NIP-44, aber das eigene Bundle reist mit
    MeshMessage *first = [a.messenger send:@"erste" to:b.pubkey replyTo:nil];
    MeshEvent *wire = a.outbox.lastObject;
    check(first && ![wire.content hasPrefix:@"sg1:"], "first message NIP-44");
    [a deliverTo:b];
    check([b.store bundleForContact:a.pubkey] != nil, "bundle learned from message");
    // B antwortet über Signal (Bundle von A mit Einmal-Schlüssel)
    [b.messenger send:@"Antwort" to:a.pubkey replyTo:first.cmid];
    wire = b.outbox.lastObject;
    check([wire.content hasPrefix:@"sg1:p:"], "reply via Signal prekey message");
    [b deliverTo:a];
    MeshMessage *got = [a chatWith:b].lastObject;
    check([got.content isEqualToString:@"Antwort"] && [got.replyTo isEqualToString:first.cmid], "A reads Signal reply");
    // Jetzt beide Richtungen Signal, auch Steueranweisungen
    [a.messenger send:@"über Signal" to:b.pubkey replyTo:nil];
    wire = a.outbox.lastObject;
    check([wire.content hasPrefix:@"sg1:"], "A now sends Signal");
    [a deliverTo:b];
    check([[[b chatWith:a].lastObject content] isEqualToString:@"über Signal"], "B reads");
    MeshMessage *target = [b chatWith:a].lastObject;
    [b.messenger react:@"❤️" to:target in:a.pubkey];
    check([[b.outbox.lastObject content] hasPrefix:@"sg1:m:"], "reaction via Signal");
    [b deliverTo:a];
    check([[a.store messageWithKey:target.cmid chat:b.pubkey].reactPeer isEqualToString:@"❤️"], "reaction arrives");
    // Handshake beim Hinzufügen
    Device *c = [[Device alloc] initNamed:@"sc" signal:YES];
    [c.store upsertContact:a.pubkey name:@"A" accepted:YES];
    [a.store upsertContact:c.pubkey name:@"C" accepted:YES];
    check([c.messenger sayHelloTo:a.pubkey] && [c deliverTo:a] == 0, "hello is invisible");
    check([a.store bundleForContact:c.pubkey] != nil, "hello carries the bundle");
    [a.messenger send:@"hallo C" to:c.pubkey replyTo:nil];
    check([[a.outbox.lastObject content] hasPrefix:@"sg1:p:"], "first message after hello already Signal");
    [a deliverTo:c];
    check([[[c chatWith:a].lastObject content] isEqualToString:@"hallo C"], "C reads");

    // Neue Signal-Identität eines Kontakts: Hinweis im Chat; verifiziert bleibt das alte Bundle
    MeshSignal *other = [[MeshSignal alloc] initWithStorage:[[Device alloc] initNamed:@"sx" signal:NO].store seed:[MeshKeys generate].seckey];
    NSString *before = [a.store bundleForContact:b.pubkey];
    [a.store setVerified:b.pubkey verified:YES];
    NSString *swapped = [MeshEnvelope message:@"neuer Schlüssel" cmid:@"9999999999999999" replyTo:nil timer:0 mode:MeshTimerFromRead bundle:[other bundle]];
    MeshEvent *e = [MeshEvent kind:4 content:[MeshNip44 encrypt:swapped keys:b.keys peerXonlyPub:a.keys.xonlyPub] tags:@[@[@"p", a.pubkey]]];
    [e signWithKeys:b.keys];
    [a.messenger receive:e];
    BOOL notice = NO;
    for (MeshMessage *m in [a chatWith:b]) notice |= m.kind == MeshPayloadNotice && [MeshPayload parseNotice:m.content].keyChanged;
    check(notice, "key change shows a notice");
    check([[a.store bundleForContact:b.pubkey] isEqualToString:before], "verified contact keeps the old bundle");
}

int main(void) {
    @autoreleasepool {
        Device *alice = [[Device alloc] initNamed:@"alice" signal:NO], *bob = [[Device alloc] initNamed:@"bob" signal:NO];
        testConversation(alice, bob);
        testReactions(alice, bob);
        testDelete(alice, bob);
        testTimer(alice, bob);
        testClear(alice, bob);
        testStrangers(alice, bob);
        testPicture(alice, bob);
        testLarge(alice, bob);
        testPanic(alice, bob);
        testSignal();
    }
    return testsDone();
}
