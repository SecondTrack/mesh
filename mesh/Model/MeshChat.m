#import "MeshChat.h"

NSString *const MeshTeamChat = @"team";
static NSString *const kGroupPrefix = @"g:";

NSString *MeshGroupChat(NSString *gid) { return [kGroupPrefix stringByAppendingString:gid ?: @""]; }

NSString *MeshGroupOfChat(NSString *chat) {
    return [chat hasPrefix:kGroupPrefix] && chat.length == kGroupPrefix.length + 16 ? [chat substringFromIndex:kGroupPrefix.length] : nil;
}

BOOL MeshIsTeamChat(NSString *chat) { return [chat isEqualToString:MeshTeamChat]; }

@implementation MeshChat
@end
