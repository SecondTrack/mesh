#import "MeshInboxWatcher.h"
#import "MeshRelayPool.h"
#import "MeshEvent.h"
#import "MeshPanic.h"
#import "MeshTime.h"

static const long long kMaxAge = 15 * 60;              // ältere Events (Relay-Speicher) sind nicht neu
static const long long kPanicLookback = 7 * 24 * 3600; // so weit zurück auf gespeicherte Auslöser prüfen
static const NSUInteger kMaxSeen = 2000;

@interface MeshInboxWatcher () <MeshRelayPoolDelegate>
@end

@implementation MeshInboxWatcher {
    NSArray *_pubkeys;
    MeshRelayPool *_pool;
    MeshPanic *_panic;
    NSMutableSet *_seen;
    long long _since;
}

- (instancetype)initWithPubkeys:(NSArray *)pubkeys relays:(NSArray *)urls panic:(MeshPanic *)panic {
    if ((self = [super init])) {
        _pubkeys = [pubkeys copy];
        _panic = panic;
        _seen = [NSMutableSet set];
        _pool = [[MeshRelayPool alloc] initWithURLs:urls];
        _pool.delegate = self;
    }
    return self;
}

- (void)dealloc { _pool.delegate = nil; [_pool stop]; }

- (void)start {
    _since = MeshNow();
    if (_pubkeys.count) [_pool start];
}

- (void)stop { [_pool stop]; }
- (void)keepAlive { [_pool reconnectNow]; }

// Neues live (ohne since: die Absenderuhr kann falsch gehen); dazu die letzten Tage, damit ein
// Auslöser wirkt, der ankam, während das Gerät offline war. Aus dem Verlauf zählt nur der Auslöser.
- (NSDictionary *)subscriptionsForPool:(MeshRelayPool *)pool {
    return @{ @"mesh-watch": @{ @"kinds": @[@4], @"#p": _pubkeys, @"limit": @0 },
              @"mesh-watch-history": @{ @"kinds": @[@4], @"#p": _pubkeys, @"since": @(MAX(0, _since - kPanicLookback)) } };
}

- (NSArray *)pendingEventsForPool:(MeshRelayPool *)pool { return nil; }
- (MeshEvent *)pool:(MeshRelayPool *)pool authEventForRelay:(NSString *)url challenge:(NSString *)challenge { return nil; }
- (void)pool:(MeshRelayPool *)pool didStoreEvent:(NSString *)eventId {}

- (void)pool:(MeshRelayPool *)pool didReceiveEvent:(MeshEvent *)event subId:(NSString *)subId {
    if (event.kind != 4 || [_seen containsObject:event.eventId] || [_pubkeys containsObject:event.pubkey]) return;
    BOOL mine = NO;
    for (NSString *pk in _pubkeys) mine |= [event hasTag:@"p" value:pk];
    if (!mine) return;
    if (_seen.count >= kMaxSeen) [_seen removeAllObjects];   // begrenzt; Doppeltes danach höchstens eine Meldung
    [_seen addObject:event.eventId];
    for (NSArray *tag in event.tags)
        if (tag.count >= 2 && [tag[0] isEqual:@"mw"] && [_panic matchesTrigger:tag[1] sentAt:event.createdAt]) { [self.delegate watcherSawPanic:self]; return; }
    if (event.createdAt < _since - kMaxAge) return;
    [self.delegate watcherSawNewMessage:self];
}

@end
