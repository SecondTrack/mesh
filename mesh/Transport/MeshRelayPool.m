#import "MeshRelayPool.h"
#import "MeshEvent.h"
#import "MeshTor.h"
#import "MeshNotifications.h"

static const NSTimeInterval kBackoffMin = 5, kBackoffMax = 120, kTick = 5;
static const NSTimeInterval kStableAfter = 60;   // erst eine so lange gehaltene Verbindung setzt den Backoff zurück
static const NSUInteger kMaxPendingEvents = 200;
static const NSTimeInterval kJitterMin = 5, kJitterMax = 60, kJitterTick = 1;

// Gleichverteilt in [lo, hi] (Millisekunden-Raster).
static NSTimeInterval randomBetween(NSTimeInterval lo, NSTimeInterval hi) {
    return lo + arc4random_uniform((uint32_t)((hi - lo) * 1000) + 1) / 1000.0;
}

@interface MeshRelayPool () <MeshRelayDelegate>
@end

@implementation MeshRelayPool {
    NSArray *_relays;                 // MeshRelay*
    MeshVerifiedEvents *_verified;    // geprüfte Event-IDs, geteilt von allen Relays des Pools
    NSMutableDictionary *_nextTry;    // url -> NSDate
    NSMutableDictionary *_backoff;    // url -> NSNumber (Sekunden)
    NSMutableDictionary *_upSince;    // url -> NSDate der aktuellen Verbindung
    NSMutableSet *_authSent;          // urls, an die in der aktuellen Verbindung AUTH ging
    NSMutableDictionary *_sentTo;     // eventId -> NSSet der urls, die es bekommen haben
    NSMutableDictionary *_sentOnConnection;   // url -> NSMutableSet der Event-IDs dieser Verbindung (Nachreichen)
    NSMutableSet *_wantsMore;         // urls, die etwas abgelehnt haben: bei Leerlauf/OK nachreichen
    NSTimer *_timer;
    BOOL _running;
}

- (instancetype)initWithURLs:(NSArray *)urls { return [self initWithURLs:urls isolation:nil]; }

- (instancetype)initWithURLs:(NSArray *)urls isolation:(NSString *)credential {
    if ((self = [super init])) {
        _verified = [[MeshVerifiedEvents alloc] init];
        _isolated = credential.length > 0;
        NSMutableArray *rs = [NSMutableArray array];
        for (NSString *u in urls) {
            MeshRelay *r = [[MeshRelay alloc] initWithURL:u];
            r.socksCredential = _isolated ? credential : nil;
            r.verified = _verified;
            r.delegate = self;
            [rs addObject:r];
        }
        _relays = rs;
        _nextTry = [NSMutableDictionary dictionary];
        _backoff = [NSMutableDictionary dictionary];
        _authSent = [NSMutableSet set];
        _timeUnit = 1;
        _sentTo = [NSMutableDictionary dictionary];
        _sentOnConnection = [NSMutableDictionary dictionary];
        _wantsMore = [NSMutableSet set];
        _jitter = _isolated;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(transportChanged)
                                                     name:MeshTransportChangedNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_timer invalidate];
    for (MeshRelay *r in _relays) r.delegate = nil;   // Lese-Threads können den Pool überleben
}

- (NSUInteger)relayCount { return _relays.count; }

- (NSUInteger)connectedCount {
    NSUInteger n = 0;
    for (MeshRelay *r in _relays) if (r.connected) n++;
    return n;
}

- (BOOL)anyConnected {
    for (MeshRelay *r in _relays) if (r.connected) return YES;
    return NO;
}

- (void)start {
    if (_running) return;
    _running = YES;
    [_nextTry removeAllObjects];
    [_backoff removeAllObjects];
    _timer = [NSTimer scheduledTimerWithTimeInterval:(_jitter ? kJitterTick : kTick) * _timeUnit target:self selector:@selector(tick) userInfo:nil repeats:YES];
    [self tick];   // mit jitter: legt nur die Zufallspausen fest
}

// Mit jitter keine Reaktion im selben Moment: den Übergang erkennt der eigene Takt (tick), und dort
// beginnt dann eine neue Zufallspause.
- (void)transportChanged { if (!_jitter) [self tick]; }

- (void)stop {
    _running = NO;
    [_verified reset];   // nach dem Neustart (Entsperren) kommt alles noch einmal, dann zählt es wieder
    [_timer invalidate]; _timer = nil;   // der Timer hält den Pool fest, hier wieder lösen
    for (MeshRelay *r in _relays) [r disconnect];
}

// Mit Tor wird nur über Tor verbunden. Scheitert Tor, bleibt Mesh offline statt die
// IP-Adresse über eine Direktverbindung preiszugeben.
- (BOOL)transportReady {
    MeshTor *tor = [MeshTor shared];
    if (_isolated) return tor.enabled && tor.state == MeshTorReady;   // getrennt nur über Tor, nie direkt
    return !tor.enabled || tor.state == MeshTorReady;
}

- (void)tick {
    if (!_running) return;
    if (_jitter) { [self jitterTick]; return; }
    if (![self transportReady]) return;
    NSDate *now = [NSDate date];
    for (MeshRelay *r in _relays) {
        if (r.connected || r.connecting) continue;
        NSDate *due = _nextTry[r.url];
        if (due && [due timeIntervalSinceDate:now] > 0.5 * _timeUnit) continue;   // Toleranz: Takt und Backoff fallen zusammen
        NSTimeInterval b = [_backoff[r.url] doubleValue] ?: kBackoffMin;
        _nextTry[r.url] = [now dateByAddingTimeInterval:b * _timeUnit];
        _backoff[r.url] = @(MIN(b * 2, kBackoffMax));
        [r connect];
    }
}

// Je Relay: noch keine Zeit festgelegt (Start, Tor gerade bereit, Verbindung verloren) -> jetzt eine neue
// Zufallspause; fällig -> verbinden. Tor nicht bereit: alle Zeiten verwerfen (danach neu würfeln).
- (void)jitterTick {
    if (![self transportReady]) { [_nextTry removeAllObjects]; return; }
    NSDate *now = [NSDate date];
    for (MeshRelay *r in _relays) {
        if (r.connected || r.connecting) continue;
        NSDate *due = _nextTry[r.url];
        if (!due) {
            NSTimeInterval b = [_backoff[r.url] doubleValue];   // 0 nach Start oder stabiler Verbindung
            NSTimeInterval wait = randomBetween(kJitterMin, kJitterMax) + (b > 0 ? b * randomBetween(0.5, 1.5) : 0);
            _nextTry[r.url] = [now dateByAddingTimeInterval:wait * _timeUnit];
            continue;
        }
        if ([due timeIntervalSinceDate:now] > 0) continue;
        [_nextTry removeObjectForKey:r.url];   // die nächste Pause beginnt erst nach dem Trennen
        [r connect];
    }
}

- (void)publish:(MeshEvent *)event {
    for (MeshRelay *r in _relays) if (r.connected) [self publish:event on:r];
}

// Merkt sich, wohin das Event ging: nur von dort zählt ein OK. Geht die Liste über, werden
// unbestätigte vergessen; der Delegate liefert sie bei der nächsten Verbindung erneut.
- (BOOL)publish:(MeshEvent *)event on:(MeshRelay *)relay {
    if (![relay publish:event]) {   // Warteschlange voll (großes Event): bei Leerlauf nachreichen
        if (relay.connected) [_wantsMore addObject:relay.url];
        return NO;
    }
    if (!event.eventId) return YES;
    NSMutableSet *conn = _sentOnConnection[relay.url];
    if (!conn) _sentOnConnection[relay.url] = conn = [NSMutableSet set];
    if (conn.count < 4 * kMaxPendingEvents) [conn addObject:event.eventId];
    NSMutableSet *urls = _sentTo[event.eventId];
    if (!urls) {
        if (_sentTo.count >= kMaxPendingEvents) [_sentTo removeAllObjects];
        urls = _sentTo[event.eventId] = [NSMutableSet set];
    }
    [urls addObject:relay.url];
    return YES;
}

// Nachreichen an ein Relay, das abgelehnt hatte: nur, was diese Verbindung noch nicht bekommen hat.
- (void)topUp:(MeshRelay *)relay {
    if (!_running || !relay.connected || ![_wantsMore containsObject:relay.url]) return;
    if (![_delegate respondsToSelector:@selector(pendingEventsForPool:excluding:)]) { [_wantsMore removeObject:relay.url]; return; }
    if (relay.queuedBytes > 0) { [relay notifyWhenDrained]; return; }   // erst leer schreiben, dann entsiegeln
    [_wantsMore removeObject:relay.url];
    @autoreleasepool {
        NSArray *more = [_delegate pendingEventsForPool:self excluding:[_sentOnConnection[relay.url] copy] ?: [NSSet set]];
        for (MeshEvent *e in more) if (![self publish:e on:relay]) break;   // wieder voll: beim nächsten Leerlauf weiter
        if (more.count && ![_wantsMore containsObject:relay.url]) [_wantsMore addObject:relay.url];   // evtl. noch mehr dahinter
    }
}

- (void)subscribe:(NSString *)subId filter:(NSDictionary *)filter {
    for (MeshRelay *r in _relays) if (r.connected) [r subscribe:subId filter:filter];
}

- (void)unsubscribe:(NSString *)subId {
    for (MeshRelay *r in _relays) if (r.connected) [r unsubscribe:subId];
}

- (void)reconnectNow {
    if (_jitter) return;   // getrennte Verbindung: nie auf Zuruf, nur nach eigener Zufallspause
    [_nextTry removeAllObjects];
    [self tick];
}

- (void)resubscribe {
    for (MeshRelay *r in _relays) if (r.connected) [self subscribeAllOn:r];
}

- (void)postConnectionChanged {
    [[NSNotificationCenter defaultCenter] postNotificationName:MeshConnectionChangedNotification object:nil];
}

- (void)subscribeAllOn:(MeshRelay *)relay {
    NSDictionary *subs = [_delegate subscriptionsForPool:self];
    for (NSString *subId in subs) [relay subscribe:subId filter:subs[subId]];
}

#pragma mark - MeshRelayDelegate

// Backoff nicht schon beim Verbinden zurücksetzen: ein Relay, das annimmt und gleich wieder schließt
// (Rate-Limit, AUTH-Pflicht, Tor-Sperre), würde sonst alle 5 s neu angewählt (Circuit + TLS am A4).
- (void)relayDidConnect:(MeshRelay *)relay {
    if (!_upSince) _upSince = [NSMutableDictionary dictionary];
    _upSince[relay.url] = [NSDate date];
    if (!_running) { [relay disconnect]; return; }
    [_authSent removeObject:relay.url];   // frische Verbindung: wieder genau ein AUTH-Versuch
    [_sentOnConnection removeObjectForKey:relay.url];
    [_wantsMore removeObject:relay.url];
    [self subscribeAllOn:relay];
    @autoreleasepool {   // bis zu MeshOutboxMaxBytes: gleich wieder freigeben
        for (MeshEvent *e in [_delegate pendingEventsForPool:self]) if (![self publish:e on:relay]) break;
    }
    [self postConnectionChanged];
}

- (void)relayDidDrain:(MeshRelay *)relay { [self topUp:relay]; }

- (void)relay:(MeshRelay *)relay didDisconnectWithError:(NSString *)err {
    NSDate *up = _upSince[relay.url];
    [_upSince removeObjectForKey:relay.url];
    [_sentOnConnection removeObjectForKey:relay.url];
    [_wantsMore removeObject:relay.url];
    BOOL stable = up && -[up timeIntervalSinceNow] >= kStableAfter * _timeUnit;
    if (_jitter) {   // Backoff wächst bei Fehlschlägen; die Zufallspause legt jitterTick neu fest
        NSTimeInterval b = [_backoff[relay.url] doubleValue];
        _backoff[relay.url] = @(stable ? 0 : MIN(b > 0 ? b * 2 : kBackoffMin, kBackoffMax));
        [_nextTry removeObjectForKey:relay.url];
    } else if (stable) {   // lief stabil: gleich wieder versuchen
        [_backoff removeObjectForKey:relay.url];
        [_nextTry removeObjectForKey:relay.url];
    }
    [self postConnectionChanged];
}

- (void)relay:(MeshRelay *)relay didReceiveEvent:(MeshEvent *)event subId:(NSString *)subId {
    [_delegate pool:self didReceiveEvent:event subId:subId];
}

- (void)relay:(MeshRelay *)relay didGetOKForEvent:(NSString *)eventId accepted:(BOOL)ok message:(NSString *)msg {
    if (!ok || ![_sentTo[eventId] containsObject:relay.url]) return;
    [_sentTo removeObjectForKey:eventId];
    [_delegate pool:self didStoreEvent:eventId];
    [self topUp:relay];   // Platz in der Warteschlange: Abgelehntes nachreichen
}

- (void)relay:(MeshRelay *)relay didRequestAuth:(NSString *)challenge {
    if (!_running || [_authSent containsObject:relay.url]) return;
    [_authSent addObject:relay.url];
    MeshEvent *auth = [_delegate pool:self authEventForRelay:relay.url challenge:challenge];
    if (!auth) return;
    [relay sendAuth:auth];
    [self subscribeAllOn:relay];
}

@end
