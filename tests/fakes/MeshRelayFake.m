// Ersetzt MeshRelay in Tests: kein Netz, Verbindungen werden von außen ausgelöst.
#import "MeshRelayFake.h"

@implementation MeshRelay {
    BOOL _connected, _connecting;
    int _connectCalls, _sent;
}
@synthesize url = _url;

- (instancetype)initWithURL:(NSString *)u { if ((self = [super init])) _url = [u copy]; return self; }
- (BOOL)connected  { return _connected; }
- (BOOL)connecting { return _connecting; }
- (void)connect    { _connecting = YES; _connectCalls++; }
- (void)disconnect { _connecting = NO; if (_connected) [self fakeDrop]; }
- (void)subscribe:(NSString *)s filter:(NSDictionary *)f { _sent++; }
- (void)publish:(MeshEvent *)e { _sent++; }
- (void)sendAuth:(MeshEvent *)e { _sent++; }

- (int)connectCalls { return _connectCalls; }
- (int)sent { return _sent; }
- (void)fakeUp   { _connecting = NO; _connected = YES; [self.delegate relayDidConnect:self]; }
- (void)fakeDrop { _connecting = NO; _connected = NO; [self.delegate relay:self didDisconnectWithError:@"x"]; }
- (void)fakeFail { _connecting = NO; [self.delegate relay:self didDisconnectWithError:@"x"]; }
- (void)fakeOK:(NSString *)eventId { [self.delegate relay:self didGetOKForEvent:eventId accepted:YES message:@""]; }
- (void)fakeAuth { [self.delegate relay:self didRequestAuth:@"c"]; }
@end
