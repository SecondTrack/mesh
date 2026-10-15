#import "MeshTeam.h"
#import "MeshStore.h"
#import "MeshStore+Group.h"
#import "MeshStore+Chat.h"
#import "MeshRelayPool.h"
#import "MeshTor.h"
#import "MeshKeys.h"
#import "MeshEvent.h"
#import "MeshEnvelope.h"
#import "MeshNip44.h"
#import "MeshTeamPost.h"
#import "MeshGroupState.h"
#import "MeshMessage.h"
#import "MeshPayload.h"
#import "MeshChat.h"
#import "MeshHex.h"
#import "MeshCrypto.h"
#import "MeshJSON.h"
#import "MeshTime.h"
#import "MeshMemory.h"
#import "MeshL10n.h"
#import "MeshLog.h"

// TEAM_PK und TEAM_CARD (docs/TEAM_GROUPS_PROTOCOL.md, A1): die echten Werte trägt der Entwickler hier
// ein. Solange TEAM_PK nur Nullen hat, ist der Team-Chat ganz aus (kein Eintrag, kein Netzverkehr).
NSString *const MeshTeamPubkey = @"0000000000000000000000000000000000000000000000000000000000000000";
NSString *const MeshTeamCard   = @"";

static const long long kWindow = 90 * 24 * 3600;           // Rundbriefe höchstens so alt
static const long long kMaxClockSkew = 15 * 60;            // so weit in der Zukunft höchstens
static const long long kOutboxLifetime = 7 * 24 * 3600;    // wie die normale Warteschlange
static const NSUInteger kMaxReply = 64 * 1024;             // Antwort des Teams: wie Text im 1:1-Chat
static const NSUInteger kMaxDeletions = 100;               // e-Tags je kind-5
static const NSUInteger kMaxBroadcastJSON = 16 * 1024;     // content vor dem Parsen höchstens (wie Android)
static NSString *const kSubAnon = @"mesh-anon", *const kSubTeam = @"mesh-team";

@interface MeshTeam () <MeshRelayPoolDelegate>
@end

@implementation MeshTeam {
    MeshStore *_store;
    NSString *_me, *_card;
    MeshKeys *_e;            // Einweg-Schlüssel, nur entsperrt im RAM
    NSString *_ePub;
    MeshRelayPool *_pool;    // getrennte Verbindung, nur für E
    NSArray *_urls;
    MeshEvent *_last;
}

+ (BOOL)isPlaceholder:(NSString *)pk {
    if (![MeshGroupState isPubkey:pk]) return YES;
    return [[pk stringByReplacingOccurrencesOfString:@"0" withString:@""] length] == 0;
}

+ (instancetype)teamWithStore:(MeshStore *)store myPubkey:(NSString *)me {
    return [[self alloc] initWithStore:store myPubkey:me teamPubkey:MeshTeamPubkey card:MeshTeamCard];
}

- (instancetype)initWithStore:(MeshStore *)store myPubkey:(NSString *)me teamPubkey:(NSString *)teamPubkey card:(NSString *)card {
    // Platzhalter: aus. Eigene Identität ist das Team: kein Team-Chat (Entwickler-Seite gibt es nur bei Android).
    if (!store || [MeshTeam isPlaceholder:teamPubkey] || [teamPubkey.lowercaseString isEqualToString:me.lowercaseString]) return nil;
    if ((self = [super init])) {
        _store = store;
        _me = [me copy];
        _teamPubkey = teamPubkey.lowercaseString;
        _card = [card copy] ?: @"";
    }
    return self;
}

- (void)dealloc { [self lock]; }

- (BOOL)isolationAvailable { return [MeshTor shared].enabled; }

- (BOOL)muted  { return [_store teamValue:"muted"] != 0; }
- (BOOL)hidden { return [_store teamValue:"hidden"] != 0; }
- (void)setMuted:(BOOL)muted   { [_store setTeamValue:"muted" value:muted ? 1 : 0]; }
- (void)setHidden:(BOOL)hidden { [_store setTeamValue:"hidden" value:hidden ? 1 : 0]; }

- (NSString *)anonPubkey { return _ePub; }
- (MeshEvent *)lastSentEvent { return _last; }

#pragma mark - Start und Sperren

- (void)startWithRelays:(NSArray *)urls {
    _urls = [urls copy];
    [self addGreeting];
    [self loadKey];
    if (!_e) [self newKey];
    [self scheduleStart];
}

// Die getrennte Verbindung soll nie im selben Moment wie die der Identität aufgehen (ein Relay könnte
// die beiden sonst über die Zeit verknüpfen): ihr Pool (jitter) wartet vor JEDEM Verbinden und
// Wiederverbinden eine eigene Zufallspause von 5–60 s, auch nach dem Entsperren und wenn Tor bereit wird.
- (void)scheduleStart {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(startPool) object:nil];
    if (!_e || !_urls.count || !self.isolationAvailable) return;
    [self startPool];
}

- (void)lock {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(startPool) object:nil];
    _pool.delegate = nil;
    [_pool stop];
    _pool = nil;
    [_e wipe];
    _e = nil;
    _ePub = nil;
}

// Begrüßung (lokal, nie übers Netz) und die Karte "Mesh Team", einmal beim ersten Start.
- (void)addGreeting {
    if ([_store teamValue:"started"]) return;
    long long now = MeshNow();
    if (![_store setTeamValue:"started" value:now]) return;
    MeshMessage *hi = [[MeshMessage alloc] init];
    hi.ts = now;
    hi.status = MeshMessageDelivered;
    hi.sender = MeshSenderApp;
    [_store insertMessage:hi chat:MeshTeamChat content:L(@"Hi and welcome to Mesh! 👋\nThis is where you get news and updates. If something doesn't work or you have an idea, just write here – anonymously.\nTo chat with the developer directly (with pictures too): add the contact below. The team will then see your Mesh ID.")];
    if (!_card.length) return;
    MeshMessage *card = [[MeshMessage alloc] init];
    card.ts = now;
    card.status = MeshMessageDelivered;
    card.sender = MeshSenderApp;
    [_store insertMessage:card chat:MeshTeamChat content:[MeshPayload contentWithContactName:@"Mesh Team" code:_card]];
}

- (void)loadKey {
    if (_e) return;
    NSString *hex = [_store teamKey];
    NSData *sk = hex ? [MeshHex decode:hex] : nil;
    _e = sk.length == 32 ? [MeshKeys fromSeckey:sk] : nil;
    MeshWipe(sk);
    _ePub = _e ? [MeshHex encode:_e.xonlyPub] : nil;
}

// Neuer E: zufällig, nie aus der Identität abgeleitet.
- (BOOL)newKey {
    MeshKeys *k = [MeshKeys generate];
    NSData *sk = k.seckey;
    NSString *hex = sk ? [MeshHex encode:sk] : nil;
    MeshWipe(sk);
    if (!hex || ![_store setTeamKey:hex]) return NO;
    [_e wipe];
    _e = k;
    _ePub = [MeshHex encode:k.xonlyPub];
    return YES;
}

- (void)startPool {
    if (_pool || !_e || !_urls.count || !self.isolationAvailable) return;   // ohne Tor keine getrennte Verbindung
    NSString *credential = [MeshHex encode:[MeshCrypto randomBytes:16]];    // eigene SOCKS-Zugangsdaten = eigener Kreis
    _pool = [[MeshRelayPool alloc] initWithURLs:_urls isolation:credential];
    _pool.jitter = YES;   // ohnehin Standard bei isolation; hier ausdrücklich
    _pool.delegate = self;
    [_pool start];
}

// Die Warteschlange des alten E geht mit (deleteTeamPersonal): nichts davon über die neue Verbindung.
- (void)startOver {
    [_store deleteTeamPersonal];
    _pool.delegate = nil;
    [_pool stop];
    _pool = nil;
    [self newKey];
    [self scheduleStart];   // neue Zugangsdaten = neuer Tor-Kreis
    [self.delegate teamChanged:self];
}

#pragma mark - Rundbriefe

- (NSDictionary *)broadcastFilter {
    long long since = [_store teamValue:"since"];
    long long from = since > 0 ? since + 1 : MeshNow() - kWindow;
    return @{ @"kinds": @[@1, @5], @"authors": @[_teamPubkey], @"since": @(MAX(0, from)) };
}

static BOOL preferGerman(void) {
    NSString *lang = [[[NSBundle mainBundle] preferredLocalizations] firstObject];
    return [lang hasPrefix:@"de"];
}

- (BOOL)receiveBroadcast:(MeshEvent *)event {
    if (![event.pubkey.lowercaseString isEqualToString:_teamPubkey] || ![event verify]) return NO;
    long long now = MeshNow();
    if (event.createdAt > now + kMaxClockSkew) return NO;
    if (event.kind == 5) return [self receiveDeletion:event];
    if (event.kind != 1 || ![event hasTag:@"t" value:@"mesh-team"]) return NO;
    if (event.createdAt < now - kWindow || [_store hasEventId:event.eventId] || [_store isDeleted:event.eventId]) return NO;
    NSData *json = [event.content dataUsingEncoding:NSUTF8StringEncoding];   // klein und flach, bevor geparst wird
    if (json.length > kMaxBroadcastJSON || !MeshJSONShallow(json, 2)) return NO;
    MeshTeamPost *post = [MeshTeamPost postFromObject:[MeshJSON objectWithData:json]];
    NSString *text = [post textPreferringGerman:preferGerman()];
    if (!text.length || [MeshPayload kindOf:text] != MeshPayloadText) return NO;   // nur Text, nie als Medium deuten
    MeshMessage *m = [[MeshMessage alloc] init];
    m.ts = event.createdAt;
    m.eventId = event.eventId;
    m.status = MeshMessageDelivered;
    m.sender = MeshSenderAll;
    if (![_store insertMessage:m chat:MeshTeamChat content:text]) return NO;
    [_store moveTeamGreetingBefore:m.ts];   // die Begrüßung bleibt die erste Blase
    [self advanceSince:event.createdAt];
    m.content = text;
    [self.delegate team:self received:m];
    return YES;
}

// kind 5 vom Team: die genannten Rundbriefe entfernen (auch später ankommende, per Tombstone).
- (BOOL)receiveDeletion:(MeshEvent *)event {
    BOOL changed = NO;
    NSUInteger n = 0;
    for (NSArray *tag in event.tags) {
        if (tag.count < 2 || ![tag[0] isEqual:@"e"] || ![MeshGroupState isPubkey:tag[1]] || ++n > kMaxDeletions) continue;
        NSString *eid = [tag[1] lowercaseString];
        MeshMessage *m = [_store messageWithKey:eid chat:MeshTeamChat];
        if (m && [m.sender isEqualToString:MeshSenderAll]) { [_store deleteMessage:m.rowId]; changed = YES; }
        else [_store rememberProcessed:eid];
    }
    [self advanceSince:event.createdAt];
    return changed;
}

- (void)advanceSince:(long long)t {
    if (t > [_store teamValue:"since"]) [_store setTeamValue:"since" value:t];
}

#pragma mark - Anonym

- (MeshMessage *)send:(NSString *)text {
    if (!self.isolationAvailable) return nil;   // keine getrennte Verbindung: nichts senden (fail-closed)
    if (!text.length || text.length > MeshTeamMaxText || [text rangeOfString:@"\1"].location != NSNotFound
        || [MeshPayload kindOf:text] != MeshPayloadText) return nil;
    if (!_e && ![self newKey]) return nil;
    MeshMessage *m = [[MeshMessage alloc] init];
    m.fromMe = YES;
    m.cmid = [MeshEnvelope newMessageId];
    // Nur NIP-44, kein Bundle, kein Bild, keine .onion, keine Panik-Felder.
    NSString *payload = [MeshNip44 encrypt:[MeshEnvelope anonMessage:text cmid:m.cmid] keys:_e peerXonlyPub:[MeshHex decode:_teamPubkey]];
    MeshEvent *e = payload ? [MeshEvent kind:4 content:payload tags:@[@[@"p", _teamPubkey]]] : nil;
    if (!e || ![e signWithKeys:_e]) return nil;
    m.ts = e.createdAt;
    m.eventId = e.eventId;
    if (![_store insertMessage:m chat:MeshTeamChat content:text]) return nil;
    NSData *json = [MeshJSON dataWithObject:[e toJSONObject]];
    [_store queueTeamEvent:[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] eventId:e.eventId created:MeshNow()];
    _last = e;
    if (_pool) [_pool publish:e];   // sonst geht sie mit der Warteschlange, sobald die Verbindung steht
    return m;
}

// Nur Events des Teams an E, nur NIP-44, nur Text.
- (BOOL)receiveAnon:(MeshEvent *)event {
    if (!_e || event.kind != 4 || ![event.pubkey.lowercaseString isEqualToString:_teamPubkey] || ![event hasTag:@"p" value:_ePub]) return NO;
    if ([_store hasEventId:event.eventId] || [_store isDeleted:event.eventId]) return NO;
    NSString *content = event.content;
    if ([content rangeOfString:@"?iv="].location != NSNotFound) { [_store rememberProcessed:event.eventId]; return NO; }   // kein NIP-04
    NSString *plain = [MeshNip44 decrypt:content keys:_e peerXonlyPub:[MeshHex decode:_teamPubkey]];
    MeshEnvelope *env = plain ? [MeshEnvelope parse:plain] : nil;
    NSString *text = env.content;
    if (env.type != MeshEnvelopeMessage || env.group || !text.length || text.length > kMaxReply || [MeshPayload kindOf:text] != MeshPayloadText) {
        [_store rememberProcessed:event.eventId];
        return NO;
    }
    MeshMessage *m = [[MeshMessage alloc] init];
    m.ts = MIN(event.createdAt, MeshNow() + kMaxClockSkew);
    m.eventId = event.eventId;
    m.cmid = env.cmid;
    m.status = MeshMessageDelivered;
    if (![_store insertMessage:m chat:MeshTeamChat content:text]) return NO;
    m.content = text;
    [self.delegate team:self received:m];
    return YES;
}

#pragma mark - MeshRelayPoolDelegate (nur die getrennte Verbindung)

// Antworten an E und die Rundbriefe: beides nur über diese Verbindung (nie über die der Identität).
- (NSDictionary *)subscriptionsForPool:(MeshRelayPool *)pool {
    if (!_ePub) return nil;
    return @{ kSubAnon: @{ @"kinds": @[@4], @"#p": @[_ePub], @"authors": @[_teamPubkey] },
              kSubTeam: [self broadcastFilter] };
}

- (NSArray *)pendingEventsForPool:(MeshRelayPool *)pool {
    if ([_store expireTeamQueuedBefore:MeshNow() - kOutboxLifetime]) [self.delegate teamChanged:self];
    NSMutableArray *events = [NSMutableArray array];
    for (NSString *json in [_store queuedTeamEvents]) {
        MeshEvent *e = [MeshEvent fromJSONObject:[MeshJSON objectWithData:[json dataUsingEncoding:NSUTF8StringEncoding]]];
        if (e) [events addObject:e];
    }
    return events;
}

// Nie mit der echten Identität anmelden (NIP-42 gäbe sie preis).
- (MeshEvent *)pool:(MeshRelayPool *)pool authEventForRelay:(NSString *)url challenge:(NSString *)challenge { return nil; }

- (void)pool:(MeshRelayPool *)pool didReceiveEvent:(MeshEvent *)event subId:(NSString *)subId {
    if (pool != _pool) return;
    BOOL changed = [subId isEqualToString:kSubAnon] ? [self receiveAnon:event]
                 : [subId isEqualToString:kSubTeam] ? [self receiveBroadcast:event] : NO;
    if (changed) [self.delegate teamChanged:self];
}

- (void)pool:(MeshRelayPool *)pool didStoreEvent:(NSString *)eventId {
    if (pool != _pool) return;
    [_store removeTeamEvent:eventId];
    if ([_store markDelivered:eventId]) [self.delegate teamChanged:self];
}

@end
