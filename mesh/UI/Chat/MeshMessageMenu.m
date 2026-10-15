#import "MeshMessageMenu.h"
#import "MeshMessage.h"
#import "MeshPayload.h"
#import "MeshSession.h"
#import "MeshPopup.h"
#import "MeshClipboard.h"
#import "MeshL10n.h"

typedef NS_ENUM(NSInteger, MeshMessageAction) { MeshActionReply, MeshActionCopy, MeshActionDelete, MeshActionDeleteForAll };

@implementation MeshMessageMenu

+ (NSArray *)reactions { return @[@"👍", @"❤️", @"😂", @"😮", @"😢", @"🙏"]; }

+ (void)showFor:(MeshMessage *)m peer:(NSString *)peer reply:(void (^)(void))reply {
    // gesendet: lässt sich beim Gegenüber finden. Team-Chat: keine Antworten, Reaktionen, Löschen für alle.
    BOOL referable = m.key.length > 0 && ![[MeshSession shared] isTeamChat:peer];
    BOOL text = m.kind == MeshPayloadText;
    NSMutableArray *titles = [NSMutableArray array], *actions = [NSMutableArray array];
    if (!m.fromMe && referable) { [titles addObject:L(@"Reply")]; [actions addObject:@(MeshActionReply)]; }
    if (text) { [titles addObject:L(@"Copy")]; [actions addObject:@(MeshActionCopy)]; }
    NSInteger red = titles.count;
    [titles addObject:m.fromMe ? L(@"Delete for me") : L(@"Delete")]; [actions addObject:@(MeshActionDelete)];
    if (m.fromMe && referable) { [titles addObject:L(@"Delete for everyone")]; [actions addObject:@(MeshActionDeleteForAll)]; }

    NSArray *emojis = !m.fromMe && referable ? [self reactions] : nil;
    [MeshPopup sheet:nil emojis:emojis options:titles destructiveFrom:red handler:^(NSInteger idx, NSString *emoji) {
        MeshSession *s = [MeshSession shared];
        if (emoji) { [s react:emoji to:m in:peer]; return; }
        if (idx < 0) return;
        switch ((MeshMessageAction)[actions[idx] integerValue]) {
            case MeshActionReply:        if (reply) reply(); break;
            case MeshActionCopy:         [MeshClipboard copyMessage:m.content]; break;
            case MeshActionDelete:       [s deleteMessage:m]; break;
            case MeshActionDeleteForAll: [s deleteForEveryone:m in:peer]; break;
        }
    }];
}

@end
