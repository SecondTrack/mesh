#import "GroupProfileViewController.h"
#import "MeshScreen.h"
#import "MeshPageHeader.h"
#import "MeshAvatarView.h"
#import "MeshControls.h"
#import "MeshMenuRow.h"
#import "MeshTheme.h"
#import "MeshGlyphs.h"
#import "MeshPopup.h"
#import "MeshL10n.h"
#import "MeshFormat.h"
#import "MeshSession.h"
#import "MeshGroupInfo.h"
#import "MeshImageViewer.h"
#import "MeshGalleryViewController.h"
#import "MeshChatMenu.h"
#import "ChatViewController.h"
#import "NewGroupViewController.h"
#import "MeshImagePicker.h"
#import "MeshImageCodec.h"
#import "MeshCaps.h"
#import "MeshClipboard.h"
#import "ContactPickerViewController.h"
#import "SafetyQRViewController.h"

static const CGFloat kAvatar = 104, kRow = 58, kRowAvatar = 40;

@implementation GroupProfileViewController {
    NSString *_chat;
    UIScrollView *_page;
    MeshGroupInfo *_info;
}

- (instancetype)initWithChat:(NSString *)chat { if ((self = [super init])) _chat = [chat copy]; return self; }

- (void)loadView {
    [self mesh_loadScreen];
    _page = [self mesh_addPageTitled:L(@"Group")];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(build) name:MeshMessagesChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(identityChanged) name:MeshIdentityChangedNotification object:nil];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)identityChanged { [self.navigationController popToRootViewControllerAnimated:NO]; }

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self build];
}

// Neu aufbauen: nach jeder Änderung (Beitritt, Umbenennen, Entfernen) kommt die Seite frisch.
- (void)build {
    if (!self.isViewLoaded) return;
    for (UIView *v in [_page.subviews copy]) [v removeFromSuperview];
    _info = [[MeshSession shared] groupInfo:_chat];
    if (!_info) return;
    MeshSession *s = [MeshSession shared];
    CGFloat W = self.view.bounds.size.width, y = 20;
    BOOL admin = _info.amAdmin && _info.canWrite;

    MeshAvatarView *av = [[MeshAvatarView alloc] initWithFrame:CGRectMake((W - kAvatar) / 2, y, kAvatar, kAvatar) source:MeshAvatarContact];
    av.pubkey = _chat;
    [_page addSubview:av];
    // Antippen: Admin wählt das Gruppenbild (B7), alle anderen sehen es groß
    UIButton *avTap = [UIButton buttonWithType:UIButtonTypeCustom];
    avTap.frame = av.frame;
    [avTap addTarget:self action:@selector(tapAvatar) forControlEvents:UIControlEventTouchUpInside];
    [_page addSubview:avTap];
    if (admin) {
        UIButton *cam = [MeshAvatarView badgeWithGlyph:@"camera" diameter:34 forAvatarFrame:av.frame];
        cam.userInteractionEnabled = YES;
        [cam addTarget:self action:@selector(tapAvatar) forControlEvents:UIControlEventTouchUpInside];
        [_page addSubview:cam];
    }
    y += kAvatar + 14;
    UILabel *name = [MeshControls userLabelWithFrame:CGRectMake(20, y, W - 40, 28) font:[MeshTheme titleFont] color:[MeshTheme ink]];
    name.text = _info.name;
    name.textAlignment = NSTextAlignmentCenter;
    [_page addSubview:name];
    y += 30;
    UILabel *count = [MeshControls labelWithFrame:CGRectMake(20, y, W - 40, 18) font:[MeshTheme previewFont] color:[MeshTheme muted]];
    count.text = [MeshFormat members:_info.members.count];
    count.textAlignment = NSTextAlignmentCenter;
    [_page addSubview:count];
    y += 30;

    NSUInteger media = [MeshGalleryViewController countFor:_chat];
    if (media)
        y = [MeshMenuRow addTo:_page y:y width:W icon:@"gallery" title:L(@"Media")
                      subtitle:[MeshFormat media:media photosOnly:YES] target:self action:@selector(openMedia)];
    if (admin) {
        y = [MeshMenuRow addTo:_page y:y width:W icon:@"chat" title:L(@"Rename") subtitle:_info.name target:self action:@selector(rename)];
        if (_info.members.count + _info.invited.count < 20)
            y = [MeshMenuRow addTo:_page y:y width:W icon:@"add" title:L(@"Add member") subtitle:L(@"From your contacts") target:self action:@selector(addMember)];
        y = [MeshMenuRow addTo:_page y:y width:W icon:@"timer" title:L(@"Disappearing messages")
                      subtitle:[MeshFormat timer:_info.timer] target:self action:@selector(changeTimer)];
        // B10: offene Gruppe mit Beitritts-Link
        y = [MeshMenuRow addTo:_page y:y width:W icon:@"globe" title:L(@"Open – anyone with the link can join")
                      subtitle:_info.open ? L(@"On") : L(@"Off") target:self action:@selector(toggleOpen)];
        if (_info.open)
            y = [MeshMenuRow addTo:_page y:y width:W icon:@"key" title:L(@"Reset link")
                          subtitle:L(@"Old links stop working") target:self action:@selector(resetLink)];
    }
    if (_info.link && _info.canWrite)
        y = [MeshMenuRow addTo:_page y:y width:W icon:@"share" title:L(@"Share link")
                      subtitle:L(@"As a card, QR code or text") target:self action:@selector(shareLink)];
    if (!_info.amAdmin && _info.canWrite)   // B9: Mitglieder schlagen eigene Kontakte vor
        y = [MeshMenuRow addTo:_page y:y width:W icon:@"add" title:L(@"Propose contact")
                      subtitle:L(@"The admin decides") target:self action:@selector(propose)];
    y += 12;

    if (admin && _info.proposals.count) {   // B9: Vorschläge der Mitglieder
        [_page addSubview:[MeshControls sectionLabelWithFrame:CGRectMake(18, y, W - 36, 14) text:L(@"PROPOSALS")]];
        y += 22;
        for (NSUInteger i = 0; i < _info.proposals.count; i++) {
            UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
            row.frame = CGRectMake(0, y, W, kRow);
            row.tag = (NSInteger)i;
            row.showsTouchWhenHighlighted = YES;
            [row addTarget:self action:@selector(tapProposal:) forControlEvents:UIControlEventTouchUpInside];
            MeshAvatarView *a = [[MeshAvatarView alloc] initWithFrame:CGRectMake(18, (kRow - kRowAvatar) / 2, kRowAvatar, kRowAvatar) source:MeshAvatarIdenticon];
            a.pubkey = _info.proposals[i][@"candidate"];
            a.userInteractionEnabled = NO;
            [row addSubview:a];
            UILabel *t = [MeshControls userLabelWithFrame:CGRectMake(18 + kRowAvatar + 14, 0, W - kRowAvatar - 50, kRow) font:[MeshTheme bodyFont] color:[MeshTheme ink]];
            t.text = _info.proposals[i][@"text"];
            [row addSubview:t];
            [_page addSubview:row];
            y += kRow;
        }
        y += 16;
    }

    [_page addSubview:[MeshControls sectionLabelWithFrame:CGRectMake(18, y, W - 36, 14) text:L(@"MEMBERS")]];
    y += 22;
    NSString *me = [s myPubkeyHex];
    NSArray *rows = [_info.members arrayByAddingObjectsFromArray:_info.invited];
    for (NSUInteger i = 0; i < rows.count; i++) {
        NSString *pk = rows[i];
        BOOL invited = i >= _info.members.count;
        UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
        row.frame = CGRectMake(0, y, W, kRow);
        row.tag = (NSInteger)i;
        row.showsTouchWhenHighlighted = YES;
        [row addTarget:self action:@selector(tapMember:) forControlEvents:UIControlEventTouchUpInside];
        // Ich mit eigenem Profilbild; Kontakte mit ihrem, Nicht-Kontakte und Kontakte ohne Bild mit Identicon (wie im Chat)
        MeshAvatarView *a = [[MeshAvatarView alloc] initWithFrame:CGRectMake(18, (kRow - kRowAvatar) / 2, kRowAvatar, kRowAvatar)
                                                           source:[pk isEqualToString:me] ? MeshAvatarSelf : MeshAvatarMember];
        a.pubkey = pk;
        a.userInteractionEnabled = NO;
        [row addSubview:a];
        UILabel *n = [MeshControls userLabelWithFrame:CGRectMake(18 + kRowAvatar + 14, 0, W - kRowAvatar - 140, kRow) font:[MeshTheme bodyFont]
                                            color:invited ? [MeshTheme muted] : [MeshTheme ink]];
        n.text = [pk isEqualToString:me] ? L(@"You") : (_info.names[pk] ?: @"");
        [row addSubview:n];
        NSString *tag = [pk isEqualToString:_info.admin] ? L(@"Admin") : invited ? L(@"invited") : nil;
        if (tag) {
            UILabel *t = [MeshControls labelWithFrame:CGRectMake(W - 100, 0, 84, kRow) font:[MeshTheme timeFont] color:[MeshTheme accent]];
            t.text = tag;
            t.textAlignment = NSTextAlignmentRight;
            [row addSubview:t];
        }
        [_page addSubview:row];
        y += kRow;
    }
    y += 16;

    BOOL handOver = admin && _info.members.count > 1;   // B9: übergeben oder auflösen
    if (_info.status == MeshGroupMember || _info.status == MeshGroupJoining || _info.status == MeshGroupLinkJoining)
        y = [MeshMenuRow addTo:_page y:y width:W icon:@"close" title:_info.amAdmin && !handOver ? L(@"Dissolve group") : L(@"Leave group")
                      subtitle:handOver ? L(@"Transfer admin or dissolve the group") : _info.amAdmin ? L(@"The group ends for everyone") : L(@"The others are informed")
                        target:self action:@selector(leave)];
    BOOL gone = _info.status == MeshGroupInviteExpired || _info.status == MeshGroupJoinFailed;
    y = [MeshMenuRow addTo:_page y:y width:W icon:@"trash" title:gone ? L(@"Remove group") : L(@"Delete chat")
                  subtitle:L(@"Removes the group and the chat on this device") target:self action:@selector(deleteGroup)];
    _page.contentSize = CGSizeMake(W, y + 20);
}

- (void)tapAvatar {
    if (!(_info.amAdmin && _info.canWrite)) {
        if (_info.hasPicture && [[MeshSession shared] pictureFor:_chat])
            [self mesh_present:[[MeshImageViewer alloc] initWithImage:[MeshAvatarView largeImageForSource:MeshAvatarContact pubkey:_chat]] animated:YES];
        return;
    }
    // Wie beim eigenen Profilbild: Kamera/Mediathek, dazu "Bild entfernen", wenn eins gesetzt ist
    BOOL cam = [MeshCaps hasCamera], has = _info.hasPicture;
    NSMutableArray *opts = [NSMutableArray array];
    if (cam) [opts addObject:L(@"Camera")];
    [opts addObject:L(@"Photo Library")];
    if (has) [opts addObject:L(@"Remove picture")];
    NSInteger removeIdx = has ? (NSInteger)opts.count - 1 : -1;
    NSString *chat = _chat;
    MESH_WEAK GroupProfileViewController *weakSelf = self;
    [MeshPopup sheet:L(@"Group picture") options:opts destructiveIndex:removeIdx handler:^(NSInteger idx) {
        if (idx < 0) return;
        if (idx == removeIdx) {
            if (![[MeshSession shared] setGroupPicture:nil chat:chat]) [MeshPopup info:L(@"Failed")];
            return;
        }
        GroupProfileViewController *me = weakSelf;
        if (!me) return;
        UIImagePickerControllerSourceType src = (cam && idx == 0)
            ? UIImagePickerControllerSourceTypeCamera : UIImagePickerControllerSourceTypePhotoLibrary;
        [MeshImagePicker pickFrom:me source:src done:^(UIImage *image) {
            NSData *jpeg = [MeshImageCodec jpegForGroupPicture:image];
            if (!jpeg || ![[MeshSession shared] setGroupPicture:jpeg chat:chat]) [MeshPopup info:L(@"Failed")];
        }];
    }];
}

- (void)openMedia {
    [self.navigationController pushViewController:[[MeshGalleryViewController alloc] initWithPeer:_chat] animated:YES];
}

- (void)rename {
    NSString *chat = _chat;
    NSString *name = _info.name ?: @"";
    [MeshPopup input:L(@"Rename group") text:name placeholder:name handler:^(NSString *text, BOOL ok) {
        if (!ok || !text.length || [text isEqualToString:name]) return;
        if (![[MeshSession shared] renameGroup:chat to:text]) [MeshPopup info:L(@"Failed")];
    }];
}

- (void)addMember {
    [self.navigationController pushViewController:[[NewGroupViewController alloc] initAddingToGroup:_chat] animated:YES];
}

- (void)changeTimer {
    MESH_WEAK GroupProfileViewController *weakSelf = self;
    [MeshChatMenu chooseTimerFor:_chat changed:^{ [weakSelf build]; }];
}

- (void)tapMember:(UIButton *)row {
    NSArray *rows = [_info.members arrayByAddingObjectsFromArray:_info.invited];
    if (row.tag >= (NSInteger)rows.count) return;
    NSString *pk = rows[row.tag], *name = _info.names[pk] ?: @"", *chat = _chat;
    MeshSession *s = [MeshSession shared];
    if ([pk isEqualToString:[s myPubkeyHex]]) return;
    BOOL contact = [s isAccepted:pk];
    BOOL removable = _info.amAdmin && _info.canWrite && ![pk isEqualToString:_info.admin];
    // B8.5: noch nicht beigetreten -> der Admin kann erneut einladen (neue Einladung, r+1)
    BOOL reinvite = removable && contact && [_info.invited containsObject:pk] && ![_info.members containsObject:pk];
    BOOL makeAdmin = removable && [_info.members containsObject:pk];   // B9: nur an beigetretene Mitglieder
    NSMutableArray *options = [NSMutableArray arrayWithObject:contact ? L(@"Open chat") : L(@"Add as contact")];
    if (reinvite) [options addObject:L(@"Invite again")];
    NSInteger adminIdx = makeAdmin ? (NSInteger)options.count : -1;
    if (makeAdmin) [options addObject:L(@"Make admin")];
    if (removable) [options addObject:L(@"Remove from group")];
    NSInteger removeIdx = removable ? (NSInteger)options.count - 1 : -1, reinviteIdx = reinvite ? 1 : -1;
    MESH_WEAK GroupProfileViewController *weakSelf = self;
    [MeshPopup sheet:name options:options destructiveIndex:removeIdx handler:^(NSInteger idx) {
        if (idx == 0 && contact) [weakSelf openChatWith:pk];
        if (idx == 0 && !contact) [weakSelf offerContact:pk name:name];
        if (idx == reinviteIdx) {
            if ([[MeshSession shared] inviteContacts:@[pk] toGroup:chat]) [MeshPopup info:L(@"Invitation sent again")];
            else [MeshPopup info:L(@"Failed")];
        }
        if (idx == adminIdx) [MeshPopup confirm:L(@"Make admin?") message:LF(@"%@ becomes the admin. You stay a member; open invitations and the group link expire.", name)
                                         action:L(@"Make admin") destructive:NO handler:^(BOOL yes) {
            if (yes && ![[MeshSession shared] transferAdmin:pk inGroup:chat leave:NO]) [MeshPopup info:L(@"Failed")];
        }];
        if (idx == removeIdx) [MeshPopup confirm:L(@"Remove from group?") message:name action:L(@"Remove") destructive:YES handler:^(BOOL yes) {
            if (yes && ![[MeshSession shared] removeMember:pk fromGroup:chat]) [MeshPopup info:L(@"Failed")];
        }];
    }];
}

- (void)openChatWith:(NSString *)pk {
    [self.navigationController pushViewController:[[ChatViewController alloc] initWithPeer:pk] animated:YES];
}

// Der normale Weg: wie eine Kontaktkarte, mit Rückfrage.
- (void)offerContact:(NSString *)pk name:(NSString *)name {
    NSString *npub = [[MeshSession shared] npubFor:pk];
    NSString *key = npub.length > 20 ? [NSString stringWithFormat:@"%@…%@", [npub substringToIndex:12], [npub substringFromIndex:npub.length - 6]] : npub;
    MESH_WEAK GroupProfileViewController *weakSelf = self;
    [MeshPopup confirm:L(@"Add contact?") message:LF(@"%@\n%@\n\nOnly add people you know.", name, key) action:L(@"Add") destructive:NO handler:^(BOOL yes) {
        if (!yes) return;
        if (![[MeshSession shared] addContact:pk name:name]) { [MeshPopup info:L(@"Failed")]; return; }
        [weakSelf openChatWith:pk];
    }];
}

- (void)leave {
    if (_info.amAdmin && _info.canWrite && _info.members.count > 1) {   // B9: übergeben und austreten oder auflösen
        MESH_WEAK GroupProfileViewController *weakSelf = self;
        [MeshPopup sheet:L(@"Leave group") options:@[L(@"Transfer admin to … and leave"), L(@"Dissolve group for everyone")] destructiveIndex:1 handler:^(NSInteger idx) {
            if (idx == 0) [weakSelf chooseNewAdminAndLeave];
            if (idx == 1) [weakSelf confirmDissolve];
        }];
        return;
    }
    [self confirmLeave];
}

- (void)confirmDissolve {
    NSString *chat = _chat;
    [MeshPopup confirm:L(@"Dissolve group?") message:L(@"The group ends for all members. The chat stays readable.") action:L(@"Dissolve") destructive:YES handler:^(BOOL yes) {
        if (yes && ![[MeshSession shared] leaveGroup:chat]) [MeshPopup info:L(@"Failed")];
    }];
}

- (void)chooseNewAdminAndLeave {
    NSString *chat = _chat, *me = [[MeshSession shared] myPubkeyHex];
    NSMutableArray *pks = [NSMutableArray array], *names = [NSMutableArray array];
    for (NSString *pk in _info.members) if (![pk isEqualToString:me]) { [pks addObject:pk]; [names addObject:_info.names[pk] ?: @""]; }
    [MeshPopup sheet:L(@"New admin") options:names destructiveIndex:-1 handler:^(NSInteger idx) {
        if (idx < 0 || idx >= (NSInteger)pks.count) return;
        NSString *pk = pks[idx];
        [MeshPopup confirm:L(@"Transfer and leave?") message:LF(@"%@ becomes the admin, then you leave the group.", names[idx]) action:L(@"Leave") destructive:YES handler:^(BOOL yes) {
            if (yes && ![[MeshSession shared] transferAdmin:pk inGroup:chat leave:YES]) [MeshPopup info:L(@"Failed")];
        }];
    }];
}

- (void)confirmLeave {
    NSString *chat = _chat;
    BOOL admin = _info.amAdmin;
    [MeshPopup confirm:admin ? L(@"Dissolve group?") : L(@"Leave group?")
               message:admin ? L(@"The group ends for all members. The chat stays readable.") : L(@"You no longer receive messages from this group.")
                action:admin ? L(@"Dissolve") : L(@"Leave") destructive:YES handler:^(BOOL yes) {
        if (yes && ![[MeshSession shared] leaveGroup:chat]) [MeshPopup info:L(@"Failed")];
    }];
}

#pragma mark - B9/B10

- (void)toggleOpen {
    NSString *chat = _chat;
    BOOL open = _info.open;
    [MeshPopup confirm:open ? L(@"Close the group?") : L(@"Open the group?")
               message:open ? L(@"The link stops working. Members stay.") : L(@"Anyone with the link can join. All members see the Mesh ID of new members.")
                action:open ? L(@"Close") : L(@"Open") destructive:NO handler:^(BOOL yes) {
        if (yes && ![[MeshSession shared] setGroupOpen:!open chat:chat]) [MeshPopup info:L(@"Failed")];
    }];
}

- (void)resetLink {
    NSString *chat = _chat;
    [MeshPopup confirm:L(@"Reset link?") message:L(@"Old links stop working. Members get the new link.") action:L(@"Reset") destructive:YES handler:^(BOOL yes) {
        if (yes && ![[MeshSession shared] resetGroupLink:chat]) [MeshPopup info:L(@"Failed")];
    }];
}

- (void)shareLink {
    NSString *chat = _chat, *link = _info.link;
    if (!link) return;
    MESH_WEAK GroupProfileViewController *weakSelf = self;
    [MeshPopup sheet:L(@"Share link") options:@[L(@"Send in a chat"), L(@"Show QR code"), L(@"Copy link")] destructiveIndex:-1 handler:^(NSInteger idx) {
        GroupProfileViewController *me = weakSelf;
        if (!me) return;
        if (idx == 0) {
            UINavigationController *nav = me.navigationController;
            ContactPickerViewController *pick = [[ContactPickerViewController alloc] initWithContacts:[[MeshSession shared] acceptedContacts]
                                                                                                 title:L(@"Send group link to…") picked:^BOOL(NSString *pk) {
                if (![[MeshSession shared] sendGroupLink:chat to:pk]) { [MeshPopup info:L(@"Failed")]; return NO; }
                [nav popToRootViewControllerAnimated:NO];
                [nav pushViewController:[[ChatViewController alloc] initWithPeer:pk] animated:YES];
                return NO;
            }];
            [nav pushViewController:pick animated:YES];
        }
        if (idx == 1)
            [me.navigationController pushViewController:[[SafetyQRViewController alloc] initWithPayload:link title:L(@"Group link")
                                                                                                  hint:L(@"Anyone who scans this code can join the group.")] animated:YES];
        if (idx == 2) { [MeshClipboard copyMessage:link]; [MeshPopup info:L(@"Link copied")]; }
    }];
}

- (void)propose {
    NSString *chat = _chat;
    ContactPickerViewController *pick = [[ContactPickerViewController alloc] initWithContacts:[[MeshSession shared] proposableContacts:chat]
                                                                                         title:L(@"Propose contact") picked:^BOOL(NSString *pk) {
        if (![[MeshSession shared] proposeContact:pk toGroup:chat]) { [MeshPopup info:L(@"Failed")]; return NO; }
        [MeshPopup info:L(@"Proposal sent to the admin")];
        return YES;
    }];
    [self.navigationController pushViewController:pick animated:YES];
}

- (void)tapProposal:(UIButton *)row {
    if (row.tag >= (NSInteger)_info.proposals.count) return;
    NSDictionary *p = _info.proposals[row.tag];
    long long pid = [p[@"id"] longLongValue];
    NSString *chat = _chat;
    [MeshPopup sheet:p[@"text"] options:@[L(@"Invite"), L(@"Decline")] destructiveIndex:1 handler:^(NSInteger idx) {
        if (idx == 0 && ![[MeshSession shared] acceptProposal:pid inGroup:chat]) [MeshPopup info:L(@"Failed")];
        if (idx == 1) [[MeshSession shared] rejectProposal:pid inGroup:chat];
    }];
}

- (void)deleteGroup {
    NSString *chat = _chat;
    MESH_WEAK GroupProfileViewController *weakSelf = self;
    [ChatViewController confirmDeleteGroup:chat done:^{ [weakSelf.navigationController popToRootViewControllerAnimated:YES]; }];
}

@end
