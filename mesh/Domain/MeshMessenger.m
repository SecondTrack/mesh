#import "MeshMessenger.h"
#import "MeshStore.h"
#import "MeshStore+Chat.h"
#import "MeshInboxPolicy.h"
#import "MeshPanic.h"
#import "MeshSignal.h"
#import "MeshStore+Signal.h"
#import "MeshKeys.h"
#import "MeshEvent.h"
#import "MeshEnvelope.h"
#import "MeshNip04.h"
#import "MeshNip44.h"
#import "MeshMessage.h"
#import "MeshPayload.h"
#import "MeshHex.h"
#import "MeshTime.h"
#import "MeshProfile.h"
#import "MeshBase64.h"
#import "MeshLog.h"

static const long long kMaxClockSkew = 15 * 60;   // Absender-Zeit höchstens so weit in der Zukunft

// Privates Profilbild (\1mesh:pic:): höchstens so viele rohe Bytes (Android: ProfilePic.MAX_RAW). Ein
// 256-px-Avatar mit Qualität 0,5 hat 10–20 KB. Dekodiert wird erst beim Anzeigen, über MeshImageCodec
// (Kopfprüfung + eigener Decoder, nie ImageIO).
static const NSUInteger kMaxPictureBytes = 64 * 1024;
static const long long kPictureReplyWindow = 10 * 60;   // nur auf frische Bilder mit dem eigenen antworten

// Base64 eines Profilbildes (auch data:-URI) -> Bytes, nur echtes JPEG/PNG bis kMaxPictureBytes. nil sonst.
static NSData *pictureBytes(NSString *picture) {
    NSString *b64 = picture;
    if ([picture hasPrefix:@"data:"]) {
        NSRange r = [picture rangeOfString:@";base64,"];
        if (r.location == NSNotFound) return nil;
        b64 = [picture substringFromIndex:NSMaxRange(r)];
    }
    if (!b64.length || b64.length > (kMaxPictureBytes + 2) / 3 * 4 + 4) return nil;
    NSData *d = [MeshBase64 decode:b64];
    if (!d.length || d.length > kMaxPictureBytes) return nil;
    const uint8_t *b = d.bytes;
    static const uint8_t png[8] = { 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A };
    BOOL jpeg = d.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF;
    BOOL isPng = d.length >= 8 && !memcmp(b, png, 8);
    return (jpeg || isPng) ? d : nil;
}

// Größte Nachricht je Art (Länge des Inhalts). Android lehnt Medien über 700 000 Zeichen ab;
// eigene Bilder sind ~60 KB, 30 s Sprache ~150 KB. Die Grenzen für Fremde stehen in MeshInboxPolicy.
static NSUInteger maxContentLength(MeshPayloadKind kind) {
    switch (kind) {
        case MeshPayloadImage: return 1024 * 1024;
        case MeshPayloadVoice: return 2 * 1024 * 1024;
        case MeshPayloadFile:  return 700 * 1000;
        default:               return 64 * 1024;
    }
}


@implementation MeshMessenger {
    MeshStore *_store;
    MeshKeys *_keys;
    MeshInboxPolicy *_inbox;
    MeshPanic *_panic;
    NSMutableDictionary *_pictureTs;   // Kontakt -> created_at des zuletzt übernommenen Bildes
    NSMutableSet *_pictureReplied;     // wem schon einmal als Antwort das eigene Bild ging (kein Ping-Pong)
}

- (instancetype)initWithStore:(MeshStore *)store keys:(MeshKeys *)keys inbox:(MeshInboxPolicy *)inbox panic:(MeshPanic *)panic {
    if ((self = [super init])) {
        _store = store; _keys = keys; _inbox = inbox; _panic = panic;
        _myPubkey = [MeshHex encode:keys.xonlyPub];
        _pictureTs = [NSMutableDictionary dictionary];
        _pictureReplied = [NSMutableSet set];
    }
    return self;
}

#pragma mark - Verschlüsseln

// Signal, wenn eine Sitzung steht oder sich mit dem Bundle des Kontakts aufbauen lässt; sonst
// NIP-44 (bis 64 KB) bzw. NIP-04 für größere Medien, das Android als Rückfall liest.
- (NSString *)encrypt:(NSString *)plain for:(NSString *)peer {
    BOOL refused = NO;
    NSString *viaSignal = [_signal encrypt:plain to:peer bundle:[_store bundleForContact:peer] verified:[_store isVerified:peer] refused:&refused];
    if (viaSignal) return viaSignal;
    if (refused) return nil;   // verifizierter Kontakt mit fremder Identität: nicht auf NIP-44 ausweichen
    NSData *peerKey = [MeshHex decode:peer];
    NSUInteger bytes = [plain lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    if (bytes <= MeshNip44MaxPlaintext) return [MeshNip44 encrypt:plain keys:_keys peerXonlyPub:peerKey];
    return [MeshNip04 encrypt:plain keys:_keys peerXonlyPub:peerKey];
}

- (NSString *)decrypt:(NSString *)payload from:(NSString *)peer {
    if ([payload hasPrefix:MeshSignalScheme]) return [_signal decrypt:payload from:peer verified:[_store isVerified:peer]];
    NSData *peerKey = [MeshHex decode:peer];
    if ([payload rangeOfString:@"?iv="].location == NSNotFound) {
        NSString *plain = [MeshNip44 decrypt:payload keys:_keys peerXonlyPub:peerKey];
        if (plain) return plain;
    }
    return [MeshNip04 decrypt:payload keys:_keys peerXonlyPub:peerKey];
}

// Eigenes Bundle für den Kontakt: mit frischem Einmal-Schlüssel, solange keine Sitzung steht
// (dann hat schon seine erste Antwort Forward Secrecy), danach das feste.
- (NSString *)ownBundleFor:(NSString *)peer {
    if (!_signal) return nil;
    return [_signal hasSessionWith:peer] ? [_signal bundle] : [_signal bundleWithFreshOneTimeKey];
}

// Bundle eines Kontakts aus einer Nachricht merken. Bei verifizierten Kontakten keine andere
// Identität: die müsste der Nutzer neu prüfen.
// Neue Identität: Hinweis im Chat; verifizierte Kontakte behalten das alte Bundle (Signal lehnt
// dann ab, bis der Nutzer neu prüft), unverifizierte übernehmen es.
- (void)rememberBundle:(NSString *)bundle of:(NSString *)peer {
    if (!bundle.length || ![_store isContact:peer]) return;
    NSString *known = [_store bundleForContact:peer];
    if ([known isEqualToString:bundle]) return;
    BOOL changed = known && ![MeshSignal bundle:known sameIdentityAs:bundle];
    if (changed) [self addNotice:[MeshPayload noticeKeyChanged] chat:peer byMe:NO];
    if (changed && [_store isVerified:peer]) return;
    [_store setBundle:bundle forContact:peer];
}

- (void)addNotice:(NSString *)content chat:(NSString *)peer byMe:(BOOL)byMe {
    MeshMessage *note = [[MeshMessage alloc] init];
    note.kind = MeshPayloadNotice;
    note.fromMe = byMe;
    note.ts = MeshNow();
    note.status = MeshMessageDelivered;
    [_store insertMessage:note chat:peer content:content];
}

- (MeshEvent *)eventWith:(NSString *)plain to:(NSString *)peer {
    if ([MeshHex decode:peer].length != 32) return nil;
    NSString *payload = [self encrypt:plain for:peer];
    if (!payload) return nil;
    MeshEvent *e = [MeshEvent kind:4 content:payload tags:@[@[@"p", peer]]];
    return [e signWithKeys:_keys] ? e : nil;
}

// Steueranweisungen erscheinen nicht im Chat, gehen aber wie Nachrichten in die Warteschlange.
- (BOOL)sendControl:(NSString *)plain to:(NSString *)peer {
    MeshEvent *e = [self eventWith:plain to:peer];
    if (e) [self.delegate messenger:self send:e];
    return e != nil;
}

#pragma mark - Senden

- (MeshMessage *)send:(NSString *)content to:(NSString *)peer replyTo:(NSString *)replyTo {
    BOOL fromSent = NO;
    int timer = [_store timerForChat:peer fromSent:&fromSent];
    MeshMessage *m = [[MeshMessage alloc] init];
    m.fromMe = YES;
    m.cmid = [MeshEnvelope newMessageId];
    m.replyTo = replyTo;
    m.timer = timer;
    NSString *plain = [MeshEnvelope message:content cmid:m.cmid replyTo:replyTo timer:timer
                                       mode:fromSent ? MeshTimerFromSent : MeshTimerFromRead bundle:[self ownBundleFor:peer]];
    MeshEvent *e = [self eventWith:plain to:peer];
    if (!e) return nil;
    m.ts = e.createdAt;
    m.eventId = e.eventId;
    // "Ab Gesendet" läuft sofort; "Ab Gesehen" startet bei Zustellung (MeshStore markDelivered:).
    if (timer > 0 && fromSent) m.expiresAt = m.ts + timer;

    if (![_store isAccepted:peer]) {   // wer antwortet, nimmt den Kontakt an
        [_store upsertContact:peer name:@"" accepted:YES];
        [self.delegate messenger:self acceptedContact:peer];
    }
    if (![_store insertMessage:m chat:peer content:content]) return nil;
    [self.delegate messenger:self send:e];
    return m;
}

- (BOOL)react:(NSString *)emoji to:(MeshMessage *)message in:(NSString *)peer {
    NSString *key = message.key;
    if (!key.length) return NO;
    NSString *next = [message.reactMine isEqualToString:emoji] ? @"" : (emoji ?: @"");
    if (![_store setReaction:next mine:YES key:key chat:peer]) return NO;
    message.reactMine = next.length ? next : nil;
    return [self sendControl:[MeshEnvelope reactionTo:key emoji:next] to:peer];
}

- (BOOL)deleteForEveryone:(MeshMessage *)message in:(NSString *)peer {
    if (!message.fromMe || !message.key.length) return NO;
    [_store deleteMessage:message.rowId];
    return [self sendControl:[MeshEnvelope deletionOf:message.key] to:peer];
}

- (void)clearChat:(NSString *)peer forEveryone:(BOOL)everyone {
    [_store clearChat:peer at:MeshNow()];
    if (everyone) [self sendControl:[MeshEnvelope clearChat] to:peer];
}

- (int)timerFor:(NSString *)peer fromSent:(BOOL *)fromSent { return [_store timerForChat:peer fromSent:fromSent]; }

- (void)setTimer:(int)seconds fromSent:(BOOL)fromSent for:(NSString *)peer {
    [self applyTimer:MAX(0, seconds) fromSent:fromSent chat:peer byMe:YES];
    [self sendControl:[MeshEnvelope timer:MAX(0, seconds) mode:fromSent ? MeshTimerFromSent : MeshTimerFromRead] to:peer];
}

// Timer übernehmen; geänderte Dauer als Hinweis in den Verlauf (wie Android).
- (BOOL)applyTimer:(int)seconds fromSent:(BOOL)fromSent chat:(NSString *)peer byMe:(BOOL)byMe {
    int before = [_store timerForChat:peer fromSent:NULL];
    [_store setTimer:seconds fromSent:fromSent chat:peer];
    if (before == seconds) return NO;
    [self addNotice:[MeshPayload noticeTimer:seconds byMe:byMe] chat:peer byMe:byMe];
    return YES;
}

- (BOOL)sayHelloTo:(NSString *)peer {
    NSString *bundle = [self ownBundleFor:peer];
    return bundle && [self sendControl:[MeshEnvelope helloWithBundle:bundle] to:peer];
}

#pragma mark - Profilbild

// Eigenes Bild in Sendeform: gespeichert ist Base64-JPEG (256 px); zu Großes geht nicht mit.
- (NSString *)ownPicture {
    NSString *pic = [_store loadProfile].picture;
    if (!pic.length) return @"";
    NSData *d = pictureBytes(pic);
    if (!d) { MeshLog(@"Profilbild: zu groß oder kein JPEG/PNG, nicht gesendet"); return nil; }
    return [MeshBase64 encode:d];
}

- (BOOL)sendPictureTo:(NSString *)peer {
    NSString *pic = [self ownPicture];
    return pic.length && [self sendControl:[MeshEnvelope picture:pic] to:peer];
}

- (void)sendPictureToAllContacts {
    NSString *pic = [self ownPicture];
    if (!pic) return;
    for (NSString *peer in [_store acceptedContactPubkeys]) if (![_store isBlocked:peer]) [self sendControl:[MeshEnvelope picture:pic] to:peer];
}

// Nur von angenommenen Kontakten; geprüft (Größe, JPEG/PNG), gespeichert wird das Base64.
- (void)receivePicture:(NSString *)picture from:(NSString *)peer at:(long long)createdAt {
    NSData *d = picture.length ? pictureBytes(picture) : nil;
    if (picture.length && !d) return;
    if (createdAt < [_pictureTs[peer] longLongValue]) return;   // ältere Kopie von einem Relay
    _pictureTs[peer] = @(createdAt);
    if ([_store setPicture:(d ? [MeshBase64 encode:d] : @"") forContact:peer]
        && [self.delegate respondsToSelector:@selector(messenger:changedPictureOf:)])
        [self.delegate messenger:self changedPictureOf:peer];
    // Einmal mit dem eigenen antworten: unser erstes kam evtl., als die Gegenseite uns noch nicht angenommen hatte.
    // (Gemerkt wird nur ein tatsächlich gesendetes: ohne eigenes Bild antwortet ein späteres.)
    if (d && MeshNow() - createdAt < kPictureReplyWindow && ![_pictureReplied containsObject:peer]
        && [self sendPictureTo:peer]) [_pictureReplied addObject:peer];
}

- (BOOL)sendPanicTrigger:(NSString *)codeword to:(NSString *)peer {
    NSString *token = [MeshPanic triggerFor:codeword target:peer];
    if (!token) return NO;
    MeshEvent *e = [MeshEvent kind:4 content:@"" tags:@[@[@"p", peer], @[@"mw", token]]];
    if (![e signWithKeys:_keys]) return NO;
    [self.delegate messenger:self send:e];
    return YES;
}

- (void)chatOpened:(NSString *)peer { [_store startTimersInChat:peer now:MeshNow()]; }

- (BOOL)deleteExpired { return [_store deleteExpiredAt:MeshNow()] > 0; }

- (NSTimeInterval)secondsUntilNextExpiry {
    long long next = [_store nextExpiry];
    return next ? MAX(0, next - MeshNow()) : -1;
}

#pragma mark - Empfangen

- (BOOL)receive:(MeshEvent *)event {
    if (event.kind != 4) return NO;
    NSString *peer = event.pubkey;
    // NIP-04 hat keinen MAC: ein fremdes DM könnte zufällig "entschlüsseln". Nur was an mich geht.
    if (![event hasTag:@"p" value:_myPubkey] || [peer isEqualToString:_myPubkey]) return NO;
    if ([_store hasEventId:event.eventId] || [_store isDeleted:event.eventId] || [_store isBlocked:peer]) return NO;
    // Notlöschung per Token, ohne zu entschlüsseln (wie Android: von jedem, der das Codewort kennt).
    for (NSArray *tag in event.tags)
        if (tag.count >= 2 && [tag[0] isEqual:@"mw"] && [_panic matchesTrigger:tag[1] sentAt:event.createdAt]) { [self.delegate messengerReceivedPanic:self]; return NO; }
    if (event.createdAt < [_store clearedAt:peer]) return NO;   // vor dem Leeren geschrieben

    NSString *plain = [self decrypt:event.content from:peer];
    if (!plain) { [self discard:event]; return NO; }   // sonst rechnet jedes Neuverbinden es wieder durch
    MeshEnvelope *env = [MeshEnvelope parse:plain];
    if (env.type == MeshEnvelopeMessage) return [self receiveMessage:env event:event];

    // Steueranweisungen nur von bekannten Kontakten; einmal angewendet, nie wieder.
    [self rememberBundle:env.bundle of:peer];
    BOOL known = [_store isContact:peer];
    switch (env.type) {
        case MeshEnvelopeMessage:
            return NO;
        case MeshEnvelopeReaction:
            if (!known) return NO;
            [_store rememberProcessed:event.eventId];
            return [_store setReaction:env.emoji mine:NO key:env.target chat:peer];
        case MeshEnvelopeDelete:
            if (!known) return NO;
            [_store rememberProcessed:event.eventId];
            return [_store deletePeerMessageWithKey:env.target chat:peer];
        case MeshEnvelopeClear:
            if (!known) return NO;
            [_store rememberProcessed:event.eventId];
            return [_store clearChat:peer at:MeshNow()];
        case MeshEnvelopeTimer:
            if (!known) return NO;
            [_store rememberProcessed:event.eventId];
            return [self applyTimer:env.timer fromSent:env.timerMode == MeshTimerFromSent chat:peer byMe:NO];
        case MeshEnvelopePicture:
            [self discard:event];   // einmal angewendet, nie wieder
            if (known && [_store isAccepted:peer]) [self receivePicture:env.picture from:peer at:event.createdAt];
            return NO;              // keine Nachricht; die Oberfläche erfährt es über den Delegate
        case MeshEnvelopeHello:
        case MeshEnvelopeFileChunk:   // nur über die .onion der Android-App, nie über Relays
        case MeshEnvelopeIgnored:
            [self discard:event];
            return NO;
    }
    return NO;
}

// Nicht lesbar oder nichts anzuzeigen: als erledigt merken (begrenzt), damit Relays es nicht bei
// jeder Verbindung erneut einspielen und Entschlüsseln erzwingen.
- (void)discard:(MeshEvent *)event {
    [_store rememberProcessed:event.eventId];
    [_store pruneTombstonesKeeping:MeshMaxTombstones];
}

- (BOOL)receiveMessage:(MeshEnvelope *)env event:(MeshEvent *)event {
    NSString *content = env.content;
    MeshPayloadKind kind = [MeshPayload kindOf:content];
    if (content.length > maxContentLength(kind)) { [self discard:event]; return NO; }
    long long bytes = (long long)[content lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    // Fremde landen als nicht angenommene Kontakte: Bilder und Profil erst nach Bestätigung.
    if (![_inbox admitFrom:event.pubkey eventId:event.eventId bytes:bytes]) return NO;
    // Codewort als Text: die teure Ableitung erst, wenn die Nachricht die Grenzen für Fremde passiert hat.
    // (nur von angenommenen Kontakten: das Codewort kennen ohnehin nur Vertraute, Fremde könnten so Rechenzeit erzwingen)
    if (kind == MeshPayloadText && [_store isAccepted:event.pubkey] && [_panic matchesText:content myPubkey:_myPubkey]) {
        [self.delegate messengerReceivedPanic:self];
        return NO;
    }

    long long t = MeshNow();
    MeshMessage *m = [[MeshMessage alloc] init];
    // Absender-Zeit ist frei wählbar: nicht weiter in der Zukunft als kMaxClockSkew (sonst klebt
    // der Chat dauerhaft oben in der Liste).
    m.ts = MIN(event.createdAt, t + kMaxClockSkew);
    m.eventId = event.eventId;
    m.cmid = env.cmid;
    m.replyTo = env.replyTo;
    m.timer = env.timer;
    m.status = MeshMessageDelivered;
    // Selbstlöschen wie Android (Disappearing.onReceived): "Ab Gesendet" ab der Absendezeit,
    // "Ab Gesehen" ab jetzt, wenn der Chat offen ist, sonst beim Öffnen.
    if (env.timer > 0) {
        if (env.timerMode == MeshTimerFromSent) m.expiresAt = event.createdAt + env.timer;
        else if ([self.openChat isEqualToString:event.pubkey]) m.expiresAt = t + env.timer;
    }
    if (![_store insertMessage:m chat:event.pubkey content:content]) return NO;
    [self rememberBundle:env.bundle of:event.pubkey];   // erst jetzt gibt es den Kontakt sicher
    m.content = content;
    [self.delegate messenger:self received:m from:event.pubkey];
    return YES;
}

@end
