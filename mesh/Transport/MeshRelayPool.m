#import "MeshRelayPool.h"
#import "MeshEvent.h"
#import "MeshTor.h"
#import "MeshNotifications.h"

static const NSTimeInterval kBackoffMin = 5, kBackoffMax = 120, kTick = 5;
static const NSUInteger kMaxPendingEvents = 200;

@interface MeshRelayPool () <MeshRelayDelegate>
@end

@implementation MeshRelayPool {
    NSArray *_relays;                 // MeshRelay*
    MeshVerifiedEvents *_verified;    // geprüfte Event-IDs, geteilt von allen Relays des Pools
    NSMutableDictionary *_nextTry;    // url -> NSDate
    NSMutableDictionary *_backoff;    // url -> NSNumber (Sekunden)
    NSMutableSet *_authSent;          // urls, an die in der aktuellen Verbindung AUTH ging
    NSMutableDictionary *_sentTo;     // eventId -> NSSet der urls, die es bekommen haben
    NSTimer *_timer;
    BOOL _running;
}

- (instancetype)initWithURLs:(NSArray *)urls {
    if ((self = [super init])) {
        _verified = [[MeshVerifiedEvents alloc] init];
        NSMutableArray *rs = [NSMutableArray array];
        for (NSString *u in urls) {
            MeshRelay *r = [[MeshRelay alloc] initWithURL:u];
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
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tick)
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
    _timer = [NSTimer scheduledTimerWithTimeInterval:kTick * _timeUnit target:self selector:@selector(tick) userInfo:nil repeats:YES];
    [self tick];
}

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
    return !tor.enabled || tor.state == MeshTorReady;
}

- (void)tick {
    if (!_running || ![self transportReady]) return;
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

- (void)publish:(MeshEvent *)event {
    for (MeshRelay *r in _relays) if (r.connected) [self publish:event on:r];
}

// Merkt sich, wohin das Event ging: nur von dort zählt ein OK. Geht die Liste über, werden
// unbestätigte vergessen; der Delegate liefert sie bei der nächsten Verbindung erneut.
- (void)publish:(MeshEvent *)event on:(MeshRelay *)relay {
    [relay publish:event];
    if (!event.eventId) return;
    NSMutableSet *urls = _sentTo[event.eventId];
    if (!urls) {
        if (_sentTo.count >= kMaxPendingEvents) [_sentTo removeAllObjects];
        urls = _sentTo[event.eventId] = [NSMutableSet set];
    }
    [urls addObject:relay.url];
}

- (void)subscribe:(NSString *)subId filter:(NSDictionary *)filter {
    for (MeshRelay *r in _relays) if (r.connected) [r subscribe:subId filter:filter];
}

- (void)reconnectNow {
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

- (void)relayDidConnect:(MeshRelay *)relay {
    [_backoff removeObjectForKey:relay.url];
    [_nextTry removeObjectForKey:relay.url];
    if (!_running) { [relay disconnect]; return; }
    [_authSent removeObject:relay.url];   // frische Verbindung: wieder genau ein AUTH-Versuch
    [self subscribeAllOn:relay];
    for (MeshEvent *e in [_delegate pendingEventsForPool:self]) [self publish:e on:relay];
    [self postConnectionChanged];
}

- (void)relay:(MeshRelay *)relay didDisconnectWithError:(NSString *)err {
    [self postConnectionChanged];
}

- (void)relay:(MeshRelay *)relay didReceiveEvent:(MeshEvent *)event subId:(NSString *)subId {
    [_delegate pool:self didReceiveEvent:event subId:subId];
}

- (void)relay:(MeshRelay *)relay didGetOKForEvent:(NSString *)eventId accepted:(BOOL)ok message:(NSString *)msg {
    if (!ok || ![_sentTo[eventId] containsObject:relay.url]) return;
    [_sentTo removeObjectForKey:eventId];
    [_delegate pool:self didStoreEvent:eventId];
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
