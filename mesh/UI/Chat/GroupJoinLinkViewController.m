#import "GroupJoinLinkViewController.h"
#import "MeshScreen.h"
#import "MeshPageHeader.h"
#import "MeshAvatarView.h"
#import "MeshControls.h"
#import "MeshTheme.h"
#import "MeshPopup.h"
#import "MeshL10n.h"
#import "MeshText.h"
#import "MeshSession.h"
#import "ChatViewController.h"

static const CGFloat kAvatar = 104, kMargin = 16;

@implementation GroupJoinLinkViewController {
    NSDictionary *_details;
    NSString *_name;
}

+ (BOOL)openIfLink:(NSString *)text name:(NSString *)name from:(UINavigationController *)nav {
    if (![[MeshSession shared] groupLinkDetails:text]) return NO;
    [nav pushViewController:[[GroupJoinLinkViewController alloc] initWithLink:text groupName:name] animated:YES];
    return YES;
}

- (instancetype)initWithLink:(NSString *)link groupName:(NSString *)name {
    if ((self = [super init])) {
        _details = [[MeshSession shared] groupLinkDetails:link];
        NSString *clean = MeshCleanName(name ?: @"");
        _name = clean.length ? clean : L(@"Group");
    }
    return self;
}

- (void)loadView {
    [self mesh_loadScreen];
    CGFloat W = self.view.bounds.size.width, y = 20, inner = W - 2 * kMargin;
    UIScrollView *page = [self mesh_addPageTitled:L(@"Join group")];
    if (!_details) return;

    MeshAvatarView *av = [[MeshAvatarView alloc] initWithFrame:CGRectMake((W - kAvatar) / 2, y, kAvatar, kAvatar) source:MeshAvatarContact];
    av.pubkey = _details[@"chat"];
    [page addSubview:av];
    y += kAvatar + 14;
    UILabel *name = [MeshControls userLabelWithFrame:CGRectMake(20, y, W - 40, 28) font:[MeshTheme titleFont] color:[MeshTheme ink]];
    name.text = _name;
    name.textAlignment = NSTextAlignmentCenter;
    [page addSubview:name];
    y += 32;
    UILabel *admin = [MeshControls userLabelWithFrame:CGRectMake(20, y, W - 40, 18) font:[MeshTheme previewFont] color:[MeshTheme muted]];
    admin.text = LF(@"Admin: %@", _details[@"adminLabel"]);
    admin.textAlignment = NSTextAlignmentCenter;
    [page addSubview:admin];
    y += 34;

    UIView *card = [MeshControls cardWithFrame:CGRectMake(kMargin, y, inner, 72)];
    UILabel *hint = [MeshControls labelWithFrame:CGRectMake(12, 6, inner - 24, 60) font:[MeshTheme previewFont] color:[MeshTheme muted]];
    hint.numberOfLines = 4;
    hint.text = L(@"All members see your Mesh ID, and you see theirs. Anyone with this link can join.");
    [card addSubview:hint];
    [page addSubview:card];
    y += 72 + 18;

    CGFloat bw = (inner - 10) / 2;
    [page addSubview:[MeshControls secondaryButtonWithFrame:CGRectMake(kMargin, y, bw, 44) title:L(@"Cancel") target:self action:@selector(cancel)]];
    [page addSubview:[MeshControls primaryButtonWithFrame:CGRectMake(kMargin + bw + 10, y, bw, 44) title:L(@"Join") target:self action:@selector(join)]];
    page.contentSize = CGSizeMake(W, y + 64);
}

- (void)join {
    NSString *chat = [[MeshSession shared] joinGroupByLink:_details[@"link"] name:_name];
    if (!chat) { [MeshPopup info:L(@"This link can't be used")]; return; }
    UINavigationController *nav = self.navigationController;
    [nav popToRootViewControllerAnimated:NO];
    [nav pushViewController:[[ChatViewController alloc] initWithPeer:chat] animated:YES];
}

- (void)cancel { [self.navigationController popViewControllerAnimated:YES]; }

@end
