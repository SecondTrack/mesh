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
@property (nonatomic, copy) NSSet *lastExcluded;
@property int excludingAsked;
@end
@implementation Spy
- (NSDictionary *)subscriptionsForPool:(MeshRelayPool *)p { self.subsAsked++; return @{ @"s": @{} }; }
- (NSArray *)pendingEventsForPool:(MeshRelayPool *)p { return self.pending; }
- (NSArray *)pendingEventsForPool:(MeshRelayPool *)p excluding:(NSSet *)ids {
    self.excludingAsked++;
    self.lastExcluded = ids;
    NSMutableArray *out = [NSMutableArray array];
    for (MeshEvent *e in self.pending) if (![ids containsObject:e.eventId]) [out addObject:e];
    return out;
}
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

    [pool stop];

    // Volle Schreib-Warteschlange: große Events abgelehnt, nach dem Leerlauf nur Fehlendes nachgereicht
    MeshRelayPool *media = [[MeshRelayPool alloc] initWithURLs:@[@"wss://m"]];
    MeshRelay *m = [[media valueForKey:@"relays"] firstObject];
    Spy *ms = [Spy new]; media.delegate = ms; media.timeUnit = kUnit;
    NSMutableArray *big = [NSMutableArray array];
    for (int i = 0; i < 5; i++) {
        MeshEvent *e = [MeshEvent kind:4 content:[@"" stringByPaddingToLength:700 * 1024 withString:@"x" startingAtIndex:0] tags:@[]];
        e.eventId = [NSString stringWithFormat:@"big%d", i];
        [big addObject:e];
    }
    ms.pending = big;
    [media start];
    [m fakeUp];
    check(m.published.count == 2 && m.refused == 1 && m.queuedBytes <= MeshRelayQueueCap, "relay queue capped: 2 of 5 large events taken");
    [m fakeWrite];
    check(ms.excludingAsked == 1 && [ms.lastExcluded isEqualToSet:[NSSet setWithObjects:@"big0", @"big1", nil]], "drain: top up without what was sent");
    check(m.published.count == 4 && m.refused == 2, "drain: next two go out, the fifth waits");
    [m fakeWrite];
    check(m.published.count == 5, "next drain: the rest goes out");
    [m fakeWrite];
    check(ms.excludingAsked == 2, "no refusal: no drain callback");
    [m fakeOK:@"big0"];
    check(ms.stored == 1 && ms.excludingAsked == 3, "OK counted; one more (empty) check for more");
    [m fakeOK:@"big1"];
    check(ms.stored == 2 && ms.excludingAsked == 3, "quiet once nothing is left");
    MeshEvent *small = [MeshEvent kind:4 content:@"hi" tags:@[]];
    small.eventId = @"small";
    [m publish:big[0]]; [m publish:big[1]]; [m publish:big[2]];
    check([m publish:small], "small events never refused");
    [media stop];

    // jitter (getrennte Verbindung): nie im selben Moment wie die Identität, eigene Pause vor jedem Verbinden
    MeshRelayPool *anon = [[MeshRelayPool alloc] initWithURLs:@[@"wss://x", @"wss://y"]];
    anon.jitter = YES;
    anon.timeUnit = kUnit;
    NSArray *ar = [anon valueForKey:@"relays"];
    MeshRelay *x = ar[0], *y = ar[1];
    Spy *as = [Spy new]; anon.delegate = as;
    [anon start];
    check(x.connectCalls == 0 && y.connectCalls == 0, "jitter: nothing at start");
    [[NSNotificationCenter defaultCenter] postNotificationName:MeshTransportChangedNotification object:nil];
    check(x.connectCalls == 0 && y.connectCalls == 0, "jitter: no reaction in the same moment as the transport notification");
    spin(4 * kUnit);
    check(x.connectCalls == 0 && y.connectCalls == 0, "jitter: at least 5 s pause");
    for (int i = 0; i < 80 && (x.connectCalls == 0 || y.connectCalls == 0); i++) spin(kUnit);
    check(x.connectCalls == 1 && y.connectCalls == 1, "jitter: both connect within 5-60 s");
    [x fakeUp];
    [anon reconnectNow];
    [x fakeDrop];
    int afterDrop = x.connectCalls;
    spin(4 * kUnit);
    check(x.connectCalls == afterDrop, "jitter: reconnect also waits at least 5 s (no lockstep after a drop)");
    for (int i = 0; i < 200 && x.connectCalls == afterDrop; i++) spin(kUnit);
    check(x.connectCalls == afterDrop + 1, "jitter: reconnects after its own pause");
    NSMutableSet *delays = [NSMutableSet set];
    for (int run = 0; run < 3; run++) {
        MeshRelayPool *p2 = [[MeshRelayPool alloc] initWithURLs:@[@"wss://z"]];
        p2.jitter = YES; p2.timeUnit = kUnit;
        [p2 start];
        NSDate *due = [[p2 valueForKey:@"nextTry"] objectForKey:@"wss://z"];
        NSTimeInterval d = [due timeIntervalSinceNow] / kUnit;
        check(d >= 4.9 && d <= 60.1, "jitter: delay in 5-60 s");
        [delays addObject:@((int)(d * 100))];
        [p2 stop];
    }
    check(delays.count > 1, "jitter: delays are random");
    [anon stop];

    return testsDone();
}}
