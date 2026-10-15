#import "MeshChatMenu.h"
#import "MeshSession.h"
#import "MeshPopup.h"
#import "MeshFormat.h"
#import "MeshL10n.h"

static const int kTimers[] = { 0, 300, 3600, 86400, 604800 };   // wie Androids TtlSheet

static NSString *checked(NSString *title, BOOL on) { return on ? [@"✓ " stringByAppendingString:title] : title; }

@implementation MeshChatMenu

+ (void)showForPeer:(NSString *)peer media:(void (^)(void))media changed:(void (^)(void))changed {
    [MeshPopup sheet:nil options:@[L(@"Media"), L(@"Disappearing messages"), L(@"Clear chat")] destructiveIndex:2 handler:^(NSInteger idx) {
        if (idx == 0 && media) media();
        if (idx == 1) [self chooseTimerFor:peer changed:changed];
        if (idx == 2) [self askClear:peer];
    }];
}

+ (void)chooseTimerFor:(NSString *)peer changed:(void (^)(void))changed {
    BOOL fromSent = NO;
    int current = [[MeshSession shared] timerFor:peer fromSent:&fromSent];
    NSMutableArray *titles = [NSMutableArray array];
    for (size_t i = 0; i < sizeof(kTimers) / sizeof(kTimers[0]); i++)
        [titles addObject:checked([MeshFormat timer:kTimers[i]], kTimers[i] == current)];
    [MeshPopup sheet:L(@"New messages disappear on both devices") options:titles destructiveIndex:-1 handler:^(NSInteger idx) {
        if (idx < 0) return;
        int seconds = kTimers[idx];
        if (!seconds) { [[MeshSession shared] setTimer:0 fromSent:NO for:peer]; if (changed) changed(); return; }
        NSArray *starts = @[checked(L(@"From seen"), !fromSent), checked(L(@"From sent"), fromSent)];
        [MeshPopup sheet:L(@"The clock starts") options:starts destructiveIndex:-1 handler:^(NSInteger start) {
            if (start < 0) return;
            [[MeshSession shared] setTimer:seconds fromSent:start == 1 for:peer];
            if (changed) changed();
        }];
    }];
}

+ (void)askClear:(NSString *)peer {
    [MeshPopup sheet:L(@"Clear this chat?") options:@[L(@"Clear for me"), L(@"Clear for everyone")] destructiveIndex:1 handler:^(NSInteger idx) {
        if (idx >= 0) [[MeshSession shared] clearChat:peer forEveryone:idx == 1];
    }];
}

@end
