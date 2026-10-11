// MeshInboxWatcher: meldet nur neue DMs an die eigenen Pubkeys, erkennt das Notlöschungs-Token
// ohne Schlüssel und ignoriert Altes, Eigenes und Doppeltes.
#import "MeshTest.h"
#import "MeshInboxWatcher.h"
#import "MeshRelayPool.h"
#import "MeshPanic.h"
#import "MeshEvent.h"
#import "MeshKeys.h"
#import "MeshHex.h"
#import "MeshTime.h"

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

@interface Listener : NSObject <MeshInboxWatcherDelegate>
@property (nonatomic) int messages, panics;
@end
@implementation Listener
- (void)watcherSawNewMessage:(MeshInboxWatcher *)w { _messages++; }
- (void)watcherSawPanic:(MeshInboxWatcher *)w { _panics++; }
@end

static MeshEvent *dm(MeshKeys *from, NSString *to, long long createdAt, NSArray *extraTags) {
    MeshEvent *e = [MeshEvent kind:4 content:@"x?iv=y" tags:[@[@[@"p", to]] arrayByAddingObjectsFromArray:extraTags ?: @[]]];
    e.createdAt = createdAt;
    [e signWithKeys:from];
    return e;
}

int main(void) { @autoreleasepool {
    MeshKeys *me = [MeshKeys generate], *other = [MeshKeys generate], *stranger = [MeshKeys generate];
    NSString *mine = [MeshHex encode:me.xonlyPub], *second = [MeshHex encode:other.xonlyPub];
    MeshPanic *panic = [[MeshPanic alloc] initWithStorage:[MemoryPanicStorage new]];
    [panic setCodeword:@"Leuchtturm" pubkeys:@[mine, second]];

    MeshInboxWatcher *w = [[MeshInboxWatcher alloc] initWithPubkeys:@[mine, second] relays:@[] panic:panic];
    Listener *l = [Listener new];
    w.delegate = l;
    [w start];
    id<MeshRelayPoolDelegate> pd = (id<MeshRelayPoolDelegate>)w;
    NSDictionary *subs = [pd subscriptionsForPool:nil];
    check([subs[@"mesh-watch"][@"#p"] isEqual:@[mine, second]] && [subs[@"mesh-watch"][@"limit"] isEqual:@0], "live filter for own pubkeys");

    long long now = MeshNow();
    MeshEvent *fresh = dm(stranger, mine, now, nil);
    [pd pool:nil didReceiveEvent:fresh subId:@"mesh-watch"];
    check(l.messages == 1, "new DM reported");
    [pd pool:nil didReceiveEvent:fresh subId:@"mesh-watch"];
    check(l.messages == 1, "duplicate ignored");
    [pd pool:nil didReceiveEvent:dm(stranger, second, now, nil) subId:@"mesh-watch"];
    check(l.messages == 2, "second identity too");
    [pd pool:nil didReceiveEvent:dm(stranger, mine, now - 3600, nil) subId:@"mesh-watch"];
    check(l.messages == 2, "old event from relay storage ignored");
    [pd pool:nil didReceiveEvent:dm(me, second, now, nil) subId:@"mesh-watch"];
    check(l.messages == 2, "own outgoing ignored");
    [pd pool:nil didReceiveEvent:dm(stranger, [MeshHex encode:stranger.xonlyPub], now, nil) subId:@"mesh-watch"];
    check(l.messages == 2, "not addressed to me");

    [pd pool:nil didReceiveEvent:dm(stranger, second, now, @[@[@"mw", @"p2:falsch"]]) subId:@"mesh-watch"];
    check(l.panics == 0, "wrong token no wipe");
    NSString *token = [MeshPanic triggerFor:@"Leuchtturm" target:second];
    [pd pool:nil didReceiveEvent:dm(stranger, second, now - 86400, @[@[@"mw", token]]) subId:@"mesh-watch-history"];
    check(l.panics == 0, "replayed trigger from before the codeword ignored");
    [pd pool:nil didReceiveEvent:dm(stranger, second, now - 600, @[@[@"mw", token]]) subId:@"mesh-watch-history"];
    check(l.panics == 1, "stored trigger wipes while locked");
    check(subs[@"mesh-watch-history"][@"since"] != nil, "history for triggers sent while offline");
    [w stop];
    return testsDone();
}}
