#import "MeshChat.h"
#import "MeshL10n.h"

NSString *const MeshTeamChat = @"team";
static NSString *const kGroupPrefix = @"g:";

NSString *MeshGroupChat(NSString *gid) { return [kGroupPrefix stringByAppendingString:gid ?: @""]; }

NSString *MeshGroupOfChat(NSString *chat) {
    return [chat hasPrefix:kGroupPrefix] && chat.length == kGroupPrefix.length + 16 ? [chat substringFromIndex:kGroupPrefix.length] : nil;
}

BOOL MeshIsTeamChat(NSString *chat) { return [chat isEqualToString:MeshTeamChat]; }

@implementation MeshChat
@end

void MeshSortChatList(NSMutableArray *chats) {
    NSArray *sorted = [chats sortedArrayWithOptions:NSSortStable usingComparator:^NSComparisonResult(MeshChat *a, MeshChat *b) {
        if (a.isTeam != b.isTeam) return a.isTeam ? NSOrderedAscending : NSOrderedDescending;
        return a.ts == b.ts ? NSOrderedSame : a.ts > b.ts ? NSOrderedAscending : NSOrderedDescending;
    }];
    [chats setArray:sorted];
}

long long MeshGroupRowTime(long long lastMessage, long long arrived) { return MAX(lastMessage, arrived); }

// Beitritt läuft automatisch (gj -> gs vom Gerät des Admins), es wartet nur, bis es online ist.
NSString *MeshGroupStatusPreview(MeshGroupStatus status) {
    switch (status) {
        case MeshGroupJoining:
        case MeshGroupLinkJoining:   return L(@"Joining…");
        case MeshGroupJoinFailed:    return L(@"Joining failed");
        case MeshGroupInviteExpired: return L(@"Invitation expired");
        default:                     return nil;
    }
}

NSString *MeshGroupStatusNote(MeshGroupStatus status) {
    switch (status) {
        case MeshGroupJoining:
        case MeshGroupLinkJoining:   return L(@"Joining… completes as soon as the admin's device is online.");
        case MeshGroupJoinFailed:    return L(@"Joining failed");
        case MeshGroupInviteExpired: return L(@"Invitation expired");
        case MeshGroupLeft:          return L(@"You left the group");
        case MeshGroupRemoved:       return L(@"You are no longer in the group");
        case MeshGroupDissolved:     return L(@"Group dissolved");
        default:                     return nil;
    }
}
