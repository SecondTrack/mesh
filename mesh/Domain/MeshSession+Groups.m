// Gruppen und Team-Chat der angezeigten Identität (siehe MeshSession.h).
#import "MeshSession+Internal.h"
#import "MeshIdentity.h"
#import "MeshMessenger.h"
#import "MeshStore.h"
#import "MeshTeam.h"
#import "MeshTor.h"
#import "MeshGroupState.h"
#import "MeshGroupInfo.h"
#import "MeshProfile.h"
#import "MeshChat.h"
#import "MeshPayload.h"
#import "MeshGroupLink.h"
#import "MeshText.h"
#import "MeshL10n.h"
#import "MeshStore+Chat.h"

@implementation MeshSession (Groups)

- (BOOL)isGroupChat:(NSString *)chat { return MeshGroupOfChat(chat) != nil; }
- (BOOL)isTeamChat:(NSString *)chat { return MeshIsTeamChat(chat); }

- (NSString *)myGroupName { return [self.active.store loadProfile].name ?: @""; }

- (NSString *)createGroupNamed:(NSString *)name members:(NSArray *)pubkeys {
    NSString *gid = [self.active.messenger createGroup:name members:pubkeys myName:[self myGroupName]];
    if (!gid) return nil;
    [self messagesChanged];
    return MeshGroupChat(gid);
}

- (MeshGroupInfo *)groupInfo:(NSString *)chat {
    NSString *gid = MeshGroupOfChat(chat);
    MeshGroupStatus status = MeshGroupInvited;
    MeshGroupState *s = gid ? [self.active.messenger groupState:gid status:&status inviter:NULL] : nil;
    if (!s) return nil;
    MeshGroupInfo *info = [[MeshGroupInfo alloc] init];
    info.chat = MeshGroupChat(s.gid);
    info.name = s.name;
    info.admin = s.admin;
    info.members = s.members;
    info.status = status;
    info.amAdmin = [s.admin isEqualToString:[self myPubkeyHex]];
    info.timer = s.timer;
    info.timerFromSent = s.timerFromSent;
    info.hasPicture = s.picture != nil;
    info.invited = info.amAdmin && status == MeshGroupMember ? [self.active.messenger pendingInvitesForGroup:s.gid] : @[];
    NSMutableDictionary *names = [NSMutableDictionary dictionary];
    for (NSString *pk in [s.members arrayByAddingObjectsFromArray:info.invited]) names[pk] = [self senderName:pk inChat:info.chat];
    info.names = names;
    info.open = s.open;
    info.link = [self.active.messenger groupLink:s.gid];
    info.adminLabel = [self adminLabel:s.admin state:s];
    NSMutableArray *proposals = [NSMutableArray array];
    if (info.amAdmin && status == MeshGroupMember)
        for (NSDictionary *p in [self.active.messenger proposalsForGroup:s.gid]) {
            NSString *c = [self.active.store isAccepted:p[@"candidate"]] ? [self displayNameFor:p[@"candidate"]]
                        : [self labelFor:p[@"candidate"] name:p[@"name"]];
            [proposals addObject:@{ @"id": p[@"id"], @"from": p[@"from"], @"candidate": p[@"candidate"],
                                    @"text": LF(@"%@ proposes %@", [self senderName:p[@"from"] inChat:info.chat], c) }];
        }
    info.proposals = proposals;
    NSString *voucher = status == MeshGroupInvited ? [self.active.messenger voucherForInvite:s.gid] : nil;
    info.voucher = voucher ? [self displayNameFor:voucher] : nil;
    return info;
}

- (BOOL)changed:(BOOL)ok { if (ok) [self messagesChanged]; return ok; }

- (BOOL)acceptGroupInvite:(NSString *)chat {
    NSString *gid = MeshGroupOfChat(chat);
    return [self changed:gid && [self.active.messenger acceptInvite:gid myName:[self myGroupName]]];
}

- (void)declineGroupInvite:(NSString *)chat {
    NSString *gid = MeshGroupOfChat(chat);
    if (gid) [self.active.messenger declineInvite:gid];
    [self messagesChanged];
}

- (BOOL)leaveGroup:(NSString *)chat {
    NSString *gid = MeshGroupOfChat(chat);
    return [self changed:gid && [self.active.messenger leaveGroup:gid]];
}

- (BOOL)deletingDissolvesGroup:(NSString *)chat {
    NSString *gid = MeshGroupOfChat(chat);
    return gid && [self.active.messenger deletingDissolves:gid];
}

- (BOOL)inviteContacts:(NSArray *)pubkeys toGroup:(NSString *)chat {
    NSString *gid = MeshGroupOfChat(chat);
    return [self changed:gid && [self.active.messenger invite:pubkeys toGroup:gid]];
}

- (BOOL)removeMember:(NSString *)pubkey fromGroup:(NSString *)chat {
    NSString *gid = MeshGroupOfChat(chat);
    return [self changed:gid && [self.active.messenger removeMember:pubkey fromGroup:gid]];
}

- (BOOL)renameGroup:(NSString *)chat to:(NSString *)name {
    NSString *gid = MeshGroupOfChat(chat);
    return [self changed:gid && [self.active.messenger renameGroup:gid to:name]];
}

- (BOOL)setGroupPicture:(NSData *)jpeg chat:(NSString *)chat {
    NSString *gid = MeshGroupOfChat(chat);
    return [self changed:gid && [self.active.messenger setGroupPicture:jpeg group:gid]];
}

#pragma mark - B9/B10

// "Name ~abcd" (erste 4 Hex gegen Nachahmung); ohne Namen "Unbekannt ~abcd".
- (NSString *)labelFor:(NSString *)pk name:(NSString *)name {
    NSString *n = MeshCleanName(name ?: @"");
    return [NSString stringWithFormat:@"%@ ~%@", n.length ? n : L(@"Unknown"), [pk substringToIndex:MIN((NSUInteger)4, pk.length)]];
}

- (NSString *)adminLabel:(NSString *)admin state:(MeshGroupState *)s {
    if ([admin isEqualToString:[self myPubkeyHex]]) return L(@"You");
    if ([self.active.store isAccepted:admin]) return [self displayNameFor:admin];
    return [self labelFor:admin name:[s nameOf:admin]];
}

- (BOOL)transferAdmin:(NSString *)pubkey inGroup:(NSString *)chat leave:(BOOL)leave {
    NSString *gid = MeshGroupOfChat(chat);
    return [self changed:gid && [self.active.messenger transferAdmin:pubkey group:gid leave:leave]];
}

- (NSArray *)proposableContacts:(NSString *)chat {
    NSString *gid = MeshGroupOfChat(chat);
    MeshGroupState *s = gid ? [self.active.messenger groupState:gid status:NULL inviter:NULL] : nil;
    NSMutableArray *out = [NSMutableArray array];
    if (!s) return out;
    for (NSString *pk in [self.active.store acceptedContactPubkeys])
        if (![s hasMember:pk] && ![self.active.store isBlocked:pk]) [out addObject:pk];
    return out;
}

- (BOOL)proposeContact:(NSString *)pubkey toGroup:(NSString *)chat {
    NSString *gid = MeshGroupOfChat(chat);   // Name: der eigene Kontaktname (B9)
    return [self changed:gid && [self.active.messenger proposeContact:pubkey name:[self displayNameFor:pubkey] group:gid]];
}

- (BOOL)acceptProposal:(long long)proposalId inGroup:(NSString *)chat {
    NSString *gid = MeshGroupOfChat(chat);
    return [self changed:gid && [self.active.messenger acceptProposal:proposalId group:gid]];
}

- (BOOL)rejectProposal:(long long)proposalId inGroup:(NSString *)chat {
    NSString *gid = MeshGroupOfChat(chat);
    return [self changed:gid && [self.active.messenger rejectProposal:proposalId group:gid]];
}

- (BOOL)setGroupOpen:(BOOL)open chat:(NSString *)chat {
    NSString *gid = MeshGroupOfChat(chat);
    return [self changed:gid && [self.active.messenger setGroupOpen:open group:gid]];
}

- (BOOL)resetGroupLink:(NSString *)chat {
    NSString *gid = MeshGroupOfChat(chat);
    return [self changed:gid && [self.active.messenger resetGroupLink:gid]];
}

// Nur im 1:1-Chat (B10): als Karte mit dem Gruppennamen.
- (BOOL)sendGroupLink:(NSString *)chat to:(NSString *)peerHex {
    NSString *gid = MeshGroupOfChat(chat), *link = gid ? [self.active.messenger groupLink:gid] : nil;
    MeshGroupState *s = link ? [self.active.messenger groupState:gid status:NULL inviter:NULL] : nil;
    if (!s || !peerHex.length || MeshGroupOfChat(peerHex) || MeshIsTeamChat(peerHex)) return NO;
    return [self sendContent:[MeshPayload contentWithGroupLinkName:s.name link:link] to:peerHex replyTo:nil];
}

- (NSDictionary *)groupLinkDetails:(NSString *)text {
    MeshGroupLink *l = [MeshGroupLink parse:text];
    if (!l) return nil;
    MeshGroupState *s = [self.active.messenger groupState:l.gid status:NULL inviter:NULL];
    NSString *label = [self.active.store isAccepted:l.admin] ? [self displayNameFor:l.admin]
                    : [self labelFor:l.admin name:[s.admin isEqualToString:l.admin] ? [s nameOf:l.admin] : nil];
    return @{ @"link": l.text, @"chat": MeshGroupChat(l.gid), @"admin": l.admin, @"adminLabel": label };
}

- (NSString *)joinGroupByLink:(NSString *)link name:(NSString *)groupName {
    NSString *name = MeshCleanName(groupName ?: @"");
    NSString *gid = [self.active.messenger joinGroupByLink:link name:(name.length ? name : L(@"Group")) myName:[self myGroupName]];
    if (!gid) return nil;
    [self messagesChanged];
    return MeshGroupChat(gid);
}

#pragma mark - Team-Chat

- (BOOL)teamChatAvailable { return self.active.team != nil; }
- (BOOL)teamCanSend { return self.active.team.isolationAvailable; }
- (BOOL)teamChatHidden { return self.active.team.hidden; }
- (BOOL)teamChatMuted { return self.active.team.muted; }
- (void)setTeamChatHidden:(BOOL)hidden { self.active.team.hidden = hidden; [self messagesChanged]; }
- (void)setTeamChatMuted:(BOOL)muted { self.active.team.muted = muted; }
- (void)startTeamChatOver { [self.active.team startOver]; [self messagesChanged]; }

@end
