#import "MeshChatMenu.h"
#import "MeshSession.h"
#import "MeshPopup.h"
#import "MeshFormat.h"
#import "MeshL10n.h"
#import "MeshGroupInfo.h"

static const int kTimers[] = { 0, 300, 3600, 86400, 604800 };   // wie Androids TtlSheet

static NSString *checked(NSString *title, BOOL on) { return on ? [@"✓ " stringByAppendingString:title] : title; }

@implementation MeshChatMenu

+ (void)showForPeer:(NSString *)peer media:(void (^)(void))media changed:(void (^)(void))changed {
    MeshSession *s = [MeshSession shared];
    if ([s isTeamChat:peer]) { [self showTeam]; return; }
    if ([s isGroupChat:peer]) {   // Leeren nur lokal; Selbstlöschen stellt nur der Admin
        [MeshPopup sheet:nil options:@[L(@"Media"), L(@"Disappearing messages"), L(@"Clear chat")] destructiveIndex:2 handler:^(NSInteger idx) {
            if (idx == 0 && media) media();
            if (idx == 1) [self chooseTimerFor:peer changed:changed];
            if (idx == 2) [MeshPopup confirm:L(@"Clear this chat?") message:L(@"Only on this device.") action:L(@"Clear for me") destructive:YES
                                     handler:^(BOOL yes) { if (yes) [[MeshSession shared] clearChat:peer forEveryone:NO]; }];
        }];
        return;
    }
    [MeshPopup sheet:nil options:@[L(@"Media"), L(@"Disappearing messages"), L(@"Clear chat")] destructiveIndex:2 handler:^(NSInteger idx) {
        if (idx == 0 && media) media();
        if (idx == 1) [self chooseTimerFor:peer changed:changed];
        if (idx == 2) [self askClear:peer];
    }];
}

// Team-Chat: stumm, neu anfangen (neuer anonymer Schlüssel), ausblenden.
+ (void)showTeam {
    MeshSession *s = [MeshSession shared];
    NSString *mute = s.teamChatMuted ? L(@"Unmute") : L(@"Mute");
    [MeshPopup sheet:nil options:@[mute, L(@"Start over"), L(@"Hide")] destructiveIndex:1 handler:^(NSInteger idx) {
        if (idx == 0) s.teamChatMuted = !s.teamChatMuted;
        if (idx == 1) [MeshPopup confirm:L(@"Start over?")
                                 message:L(@"Your messages and the team's replies are deleted on this device. You get a new anonymous key; the team can't link it to the old one.")
                                  action:L(@"Start over") destructive:YES handler:^(BOOL yes) { if (yes) [s startTeamChatOver]; }];
        if (idx == 2) [MeshPopup confirm:L(@"Hide team chat?") message:L(@"You can show it again under Me.") action:L(@"Hide") destructive:NO
                                 handler:^(BOOL yes) { if (yes) s.teamChatHidden = YES; }];
    }];
}

+ (void)chooseTimerFor:(NSString *)peer changed:(void (^)(void))changed {
    if ([[MeshSession shared] isTeamChat:peer]) return;
    MeshGroupInfo *g = [[MeshSession shared] isGroupChat:peer] ? [[MeshSession shared] groupInfo:peer] : nil;
    if (g && (!g.amAdmin || !g.canWrite)) { [MeshPopup info:L(@"Only the group admin can change this.")]; return; }
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
