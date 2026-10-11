// MeshRelayPool mit Schein-Relays: ein Verbindungsversuch je Takt, Backoff,
// kein Wiederverbinden nach stop, Abos je Verbindung, einmal AUTH, OK nur vom Empfänger.
#import "MeshTest.h"
#import "MeshRelayPool.h"
#import "MeshNotifications.h"
#import "MeshRelayFake.h"
#import "MeshEvent.h"

@interface Spy : NSObject <MeshRelayPoolDelegate>
@property int subsAsked, authAsked, stored;
@property (nonatomic, copy) NSArray *pending;
@end
@implementation Spy
- (NSDictionary *)subscriptionsForPool:(MeshRelayPool *)p { self.subsAsked++; return @{ @"s": @{} }; }
- (NSArray *)pendingEventsForPool:(MeshRelayPool *)p { return self.pending; }
- (MeshEvent *)pool:(MeshRelayPool *)p authEventForRelay:(NSString *)u challenge:(NSString *)c {
    self.authAsked++; return [MeshEvent kind:22242 content:@"" tags:@[]];
}
- (void)pool:(MeshRelayPool *)p didReceiveEvent:(MeshEvent *)e subId:(NSString *)s {}
- (void)pool:(MeshRelayPool *)p didStoreEvent:(NSString *)eventId { self.stored++; }
@end

static const NSTimeInterval kUnit = 0.02;   // 5 s Takt im Pool = 0,1 s im Test
static void spin(NSTimeInterval s) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:s]]; }

int main(void) { @autoreleasepool {
    MeshRelayPool *pool = [[MeshRelayPool alloc] initWithURLs:@[@"wss://a", @"wss://b"]];
    NSArray *rs = [pool valueForKey:@"relays"];
    MeshRelay *a = rs[0], *b = rs[1];
    Spy *spy = [Spy new]; pool.delegate = spy;
    pool.timeUnit = kUnit;
    __block int changed = 0;
    [[NSNotificationCenter defaultCenter] addObserverForName:MeshConnectionChangedNotification object:nil queue:nil
                                                  usingBlock:^(NSNotification *n) { changed++; }];

    [[NSNotificationCenter defaultCenter] postNotificationName:MeshTransportChangedNotification object:nil];
    check(a.connectCalls == 0, "no connect before start");

    [pool start];
    check(a.connectCalls == 1 && b.connectCalls == 1, "start connects all");
    [[NSNotificationCenter defaultCenter] postNotificationName:MeshTransportChangedNotification object:nil];
    check(a.connectCalls == 1, "no double connect while connecting");

    [a fakeUp];
    check(pool.anyConnected && spy.subsAsked == 1 && a.sent == 1 && changed == 1, "subscribed on connect + notified");
    MeshEvent *ev = [MeshEvent kind:4 content:@"x" tags:@[]];
    ev.eventId = @"e1";
    [pool publish:ev];
    check(a.sent == 2 && b.sent == 0, "publish only to connected");
    [b fakeOK:@"e1"];
    check(spy.stored == 0, "OK from relay that never got the event ignored");
    [a fakeOK:@"e1"];
    check(spy.stored == 1, "OK from recipient counts");

    [a fakeAuth]; [a fakeAuth];
    check(spy.authAsked == 1 && a.sent == 4, "one AUTH per connection, then resubscribe");

    [b fakeFail];
    [[NSNotificationCenter defaultCenter] postNotificationName:MeshTransportChangedNotification object:nil];
    check(b.connectCalls == 1, "failed relay waits for backoff");
    spin(5.5 * kUnit);
    check(b.connectCalls == 2, "retry after 5 s");
    [b fakeFail];
    spin(5.5 * kUnit);
    check(b.connectCalls == 2, "second retry waits 10 s");
    spin(5.5 * kUnit);
    check(b.connectCalls == 3, "retry after 10 s");

    [a fakeDrop];
    check(changed == 4, "drop notified, no feedback loop");

    [pool stop];
    int before = a.connectCalls + b.connectCalls;
    [[NSNotificationCenter defaultCenter] postNotificationName:MeshTransportChangedNotification object:nil];
    spin(5.5 * kUnit);
    check(a.connectCalls + b.connectCalls == before, "stopped pool stays quiet");
    check(!pool.anyConnected, "nothing connected after stop");

    [pool start];
    check(a.connectCalls + b.connectCalls == before + 2, "restart reconnects immediately");
    MeshEvent *queued = [MeshEvent kind:4 content:@"y" tags:@[]];
    queued.eventId = @"e2";
    spy.pending = @[queued];
    int sentBefore = a.sent;
    [a fakeUp];
    check(a.sent == sentBefore + 2, "pending events resent on connect");
    [a fakeOK:@"e2"];
    check(spy.stored == 2, "OK for resent event counts");
    [a fakeAuth];
    check(spy.authAsked == 2, "new connection may AUTH again");

    return testsDone();
}}
