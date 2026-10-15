// Ersetzt MeshRelay in Tests: kein Netz, Verbindungen werden von außen ausgelöst. Die Schreib-
// Warteschlange wird nachgebildet: publish zählt Bytes wie MeshRelay (Schätzung), fakeWrite leert sie.
#import "MeshRelayFake.h"
#import "MeshEvent.h"

@implementation MeshRelay {
    BOOL _connected, _connecting, _drainWanted;
    int _connectCalls, _sent, _refusedCount;
    long long _queued;
    NSMutableArray *_published;
}
@synthesize url = _url;

- (instancetype)initWithURL:(NSString *)u { if ((self = [super init])) { _url = [u copy]; _published = [NSMutableArray array]; } return self; }
- (BOOL)connected  { return _connected; }
- (BOOL)connecting { return _connecting; }
- (long long)queuedBytes { return _queued; }
- (void)connect    { _connecting = YES; _connectCalls++; }
- (void)disconnect { _connecting = NO; if (_connected) [self fakeDrop]; }
- (void)subscribe:(NSString *)s filter:(NSDictionary *)f { _sent++; }
- (void)unsubscribe:(NSString *)s { _sent++; }
- (BOOL)publish:(MeshEvent *)e {
    long long estimate = (long long)e.content.length + 1024;
    if (estimate > MeshRelayLargeEvent && _queued > 0 && _queued + estimate > MeshRelayQueueCap) { _refusedCount++; _drainWanted = YES; return NO; }
    _sent++;
    _queued += estimate;
    if (e.eventId) [_published addObject:e.eventId];
    return YES;
}
- (void)notifyWhenDrained { _drainWanted = YES; if (!_queued) [self fakeWrite]; }
- (void)sendAuth:(MeshEvent *)e { _sent++; }

- (int)connectCalls { return _connectCalls; }
- (int)sent { return _sent; }
- (int)refused { return _refusedCount; }
- (NSArray *)published { return _published; }
- (void)fakeUp   { _connecting = NO; _connected = YES; [_published removeAllObjects]; [self.delegate relayDidConnect:self]; }
- (void)fakeDrop { _connecting = NO; _connected = NO; _queued = 0; [self.delegate relay:self didDisconnectWithError:@"x"]; }
- (void)fakeFail { _connecting = NO; [self.delegate relay:self didDisconnectWithError:@"x"]; }
- (void)fakeOK:(NSString *)eventId { [self.delegate relay:self didGetOKForEvent:eventId accepted:YES message:@""]; }
- (void)fakeAuth { [self.delegate relay:self didRequestAuth:@"c"]; }
- (void)fakeWrite {   // alles geschrieben
    _queued = 0;
    if (_drainWanted) { _drainWanted = NO; [self.delegate relayDidDrain:self]; }
}
@end
