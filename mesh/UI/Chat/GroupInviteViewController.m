#import "GroupInviteViewController.h"
#import "MeshScreen.h"
#import "MeshPageHeader.h"
#import "MeshAvatarView.h"
#import "MeshControls.h"
#import "MeshTheme.h"
#import "MeshPopup.h"
#import "MeshL10n.h"
#import "MeshSession.h"
#import "MeshGroupInfo.h"
#import "ChatViewController.h"

static const CGFloat kAvatar = 104, kMargin = 16;

@implementation GroupInviteViewController {
    NSString *_chat;
}

- (instancetype)initWithChat:(NSString *)chat { if ((self = [super init])) _chat = [chat copy]; return self; }

- (void)loadView {
    [self mesh_loadScreen];
    CGFloat W = self.view.bounds.size.width, y = 20, inner = W - 2 * kMargin;
    UIScrollView *page = [self mesh_addPageTitled:L(@"Invitation")];
    MeshGroupInfo *g = [[MeshSession shared] groupInfo:_chat];
    if (!g) return;

    MeshAvatarView *av = [[MeshAvatarView alloc] initWithFrame:CGRectMake((W - kAvatar) / 2, y, kAvatar, kAvatar) source:MeshAvatarContact];
    av.pubkey = _chat;
    [page addSubview:av];
    y += kAvatar + 14;
    UILabel *name = [MeshControls userLabelWithFrame:CGRectMake(20, y, W - 40, 28) font:[MeshTheme titleFont] color:[MeshTheme ink]];
    name.text = g.name;
    name.textAlignment = NSTextAlignmentCenter;
    [page addSubview:name];
    y += 32;
    UILabel *admin = [MeshControls userLabelWithFrame:CGRectMake(20, y, W - 40, 18) font:[MeshTheme previewFont] color:[MeshTheme muted]];
    admin.text = LF(@"Admin: %@", g.adminLabel ?: @"");
    admin.textAlignment = NSTextAlignmentCenter;
    [page addSubview:admin];
    y += 30;

    [page addSubview:[MeshControls sectionLabelWithFrame:CGRectMake(18, y, W - 36, 14) text:L(@"MEMBERS")]];
    y += 20;
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *pk in g.members) [names addObject:g.names[pk] ?: @""];
    UILabel *members = [MeshControls userLabelWithFrame:CGRectZero font:[MeshTheme bodyFont] color:[MeshTheme ink]];
    members.numberOfLines = 0;
    members.text = [names componentsJoinedByString:@"\n"];
    CGSize ms = [members.text sizeWithFont:members.font constrainedToSize:CGSizeMake(inner, 2000) lineBreakMode:NSLineBreakByWordWrapping];
    members.frame = CGRectMake(kMargin, y, inner, ceilf(ms.height));
    [page addSubview:members];
    y += ceilf(ms.height) + 18;

    // B9: Admin unbekannt, aber von einem Kontakt vorgeschlagen -> das dazusagen
    NSString *text = L(@"If you join, all members see your Mesh ID, and you see theirs.");
    if (g.voucher) text = [NSString stringWithFormat:@"%@\n\n%@", LF(@"%@ proposed you. You don't know the admin %@ yet.", g.voucher, g.adminLabel ?: @""), text];
    UILabel *hint = [MeshControls userLabelWithFrame:CGRectZero font:[MeshTheme previewFont] color:[MeshTheme muted]];
    hint.numberOfLines = 0;
    hint.text = text;
    CGSize hs = [text sizeWithFont:hint.font constrainedToSize:CGSizeMake(inner - 24, 2000) lineBreakMode:NSLineBreakByWordWrapping];
    CGFloat ch = MAX(64, ceilf(hs.height) + 16);
    hint.frame = CGRectMake(12, 8, inner - 24, ch - 16);
    UIView *card = [MeshControls cardWithFrame:CGRectMake(kMargin, y, inner, ch)];
    [card addSubview:hint];
    [page addSubview:card];
    y += ch + 18;

    CGFloat bw = (inner - 10) / 2;
    [page addSubview:[MeshControls secondaryButtonWithFrame:CGRectMake(kMargin, y, bw, 44) title:L(@"Decline") target:self action:@selector(decline)]];
    [page addSubview:[MeshControls primaryButtonWithFrame:CGRectMake(kMargin + bw + 10, y, bw, 44) title:L(@"Join") target:self action:@selector(accept)]];
    page.contentSize = CGSizeMake(W, y + 64);
}

- (void)accept {
    if (![[MeshSession shared] acceptGroupInvite:_chat]) { [MeshPopup info:L(@"Failed")]; return; }
    UINavigationController *nav = self.navigationController;
    [nav popToRootViewControllerAnimated:NO];
    [nav pushViewController:[[ChatViewController alloc] initWithPeer:_chat] animated:YES];
}

- (void)decline {
    [[MeshSession shared] declineGroupInvite:_chat];
    [self.navigationController popViewControllerAnimated:YES];
}

@end
