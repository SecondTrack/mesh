#import "NewGroupViewController.h"
#import "MeshScreen.h"
#import "MeshPageHeader.h"
#import "MeshAvatarView.h"
#import "MeshControls.h"
#import "MeshTheme.h"
#import "MeshGlyphs.h"
#import "MeshPopup.h"
#import "MeshL10n.h"
#import "MeshSession.h"
#import "MeshGroupInfo.h"
#import "ChatViewController.h"

static const CGFloat kRow = 64, kAvatar = 44, kButton = 64;

@implementation NewGroupViewController {
    NSString *_chat;           // gesetzt: Mitglieder hinzufügen
    NSArray *_contacts;
    NSMutableSet *_picked;
    NSUInteger _max;
    NSMutableArray *_checks;   // UIImageView je Zeile
    UIButton *_done;
}

- (instancetype)initAddingToGroup:(NSString *)chat {
    if ((self = [super init])) {
        _chat = [chat copy];
        _picked = [NSMutableSet set];
        _checks = [NSMutableArray array];
        MeshSession *s = [MeshSession shared];
        MeshGroupInfo *g = chat ? [s groupInfo:chat] : nil;
        NSMutableArray *list = [NSMutableArray array];
        for (NSString *pk in [s acceptedContacts])
            if (![g.members containsObject:pk] && ![g.invited containsObject:pk]) [list addObject:pk];
        _contacts = list;
        _max = g ? (g.members.count + g.invited.count < 20 ? 20 - g.members.count - g.invited.count : 0) : 19;
    }
    return self;
}

- (instancetype)init { return [self initAddingToGroup:nil]; }

- (void)loadView {
    [self mesh_loadScreen];
    CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height;
    UIScrollView *page = [self mesh_addPageTitled:_chat ? L(@"Add member") : L(@"New group")];
    CGRect f = page.frame; f.size.height -= kButton; page.frame = f;
    if (!_contacts.count) {
        UILabel *none = [MeshControls labelWithFrame:CGRectMake(30, 60, W - 60, 60) font:[MeshTheme previewFont] color:[MeshTheme muted]];
        none.text = L(@"No contacts to add");
        none.textAlignment = NSTextAlignmentCenter;
        none.numberOfLines = 0;
        [page addSubview:none];
        return;
    }
    UILabel *hint = [MeshControls labelWithFrame:CGRectMake(18, 8, W - 36, 18) font:[MeshTheme timeFont] color:[MeshTheme muted]];
    hint.text = _max == 1 ? L(@"Choose 1 contact") : LF(@"Choose up to %lu contacts", (unsigned long)_max);
    [page addSubview:hint];
    MeshSession *s = [MeshSession shared];
    for (NSUInteger i = 0; i < _contacts.count; i++) {
        UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
        row.frame = CGRectMake(0, 30 + i * kRow, W, kRow);
        row.tag = (NSInteger)i;
        [row addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventTouchUpInside];
        MeshAvatarView *av = [[MeshAvatarView alloc] initWithFrame:CGRectMake(18, (kRow - kAvatar) / 2, kAvatar, kAvatar) source:MeshAvatarContact];
        av.pubkey = _contacts[i];
        av.userInteractionEnabled = NO;
        [row addSubview:av];
        UILabel *name = [MeshControls userLabelWithFrame:CGRectMake(18 + kAvatar + 14, 0, W - kAvatar - 100, kRow) font:[MeshTheme bodyFont] color:[MeshTheme ink]];
        name.text = [s displayNameFor:_contacts[i]];
        [row addSubview:name];
        UIImageView *check = [[UIImageView alloc] initWithFrame:CGRectMake(W - 50, (kRow - 26) / 2, 26, 26)];
        check.layer.cornerRadius = 13;
        check.layer.borderWidth = 1.5f;
        check.contentMode = UIViewContentModeCenter;
        [row addSubview:check];
        [_checks addObject:check];
        [page addSubview:row];
    }
    page.contentSize = CGSizeMake(W, 40 + _contacts.count * kRow);
    _done = [MeshControls primaryButtonWithFrame:CGRectMake(16, H - kButton + 10, W - 32, 44)
                                           title:_chat ? L(@"Invite") : L(@"Next") target:self action:@selector(done)];
    [self.view addSubview:_done];
    [self refresh];
}

- (void)refresh {
    for (NSUInteger i = 0; i < _checks.count; i++) {
        BOOL on = [_picked containsObject:_contacts[i]];
        UIImageView *c = _checks[i];
        c.backgroundColor = on ? [MeshTheme accent] : [UIColor clearColor];
        c.layer.borderColor = (on ? [MeshTheme accent] : [MeshTheme line]).CGColor;
        c.image = on ? [MeshGlyphs icon:@"check" color:[MeshTheme bg] size:16] : nil;
    }
    _done.enabled = _picked.count > 0;
    _done.alpha = _picked.count ? 1 : 0.4f;
}

- (void)toggle:(UIButton *)row {
    NSString *pk = _contacts[row.tag];
    if ([_picked containsObject:pk]) [_picked removeObject:pk];
    else if (_picked.count < _max) [_picked addObject:pk];
    else { [MeshPopup info:_max == 1 ? L(@"At most 1 member can be added.") : LF(@"At most %lu members can be added.", (unsigned long)_max)]; return; }
    [self refresh];
}

- (void)done {
    NSArray *members = [_picked allObjects];
    if (!members.count) return;
    UINavigationController *nav = self.navigationController;
    if (_chat) {
        if (![[MeshSession shared] inviteContacts:members toGroup:_chat]) { [MeshPopup info:L(@"Failed")]; return; }
        [nav popViewControllerAnimated:YES];
        return;
    }
    [MeshPopup input:L(@"Group name") message:nil placeholder:L(@"Name") secure:NO numeric:NO handler:^(NSString *text, BOOL ok) {
        NSString *name = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!ok || !name.length) return;
        NSString *chat = [[MeshSession shared] createGroupNamed:name members:members];
        if (!chat) { [MeshPopup info:L(@"Failed")]; return; }
        [nav popToRootViewControllerAnimated:NO];
        [nav pushViewController:[[ChatViewController alloc] initWithPeer:chat] animated:YES];
    }];
}

@end
