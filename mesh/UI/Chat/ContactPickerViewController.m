#import "ContactPickerViewController.h"
#import "MeshScreen.h"
#import "MeshPageHeader.h"
#import "MeshAvatarView.h"
#import "MeshControls.h"
#import "MeshTheme.h"
#import "MeshSession.h"
#import "MeshL10n.h"
#import "MeshPopup.h"
#import "ChatViewController.h"

static const CGFloat kRow = 68, kAvatar = 46;

@implementation ContactPickerViewController {
    NSString *_peer;
    void (^_sent)(void);
    NSArray *_contacts;
    NSString *_card;   // gesetzt: diese Karte an den gewählten Kontakt schicken
}

- (instancetype)initWithPeer:(NSString *)peerHex sent:(void (^)(void))sent {
    if ((self = [super init])) {
        _peer = [peerHex copy];
        _sent = [sent copy];
        NSMutableArray *list = [NSMutableArray array];
        for (NSString *pk in [[MeshSession shared] acceptedContacts]) if (![pk isEqualToString:peerHex]) [list addObject:pk];
        _contacts = list;
    }
    return self;
}

- (instancetype)initSharingContact:(NSString *)contactHex {
    if ((self = [self initWithPeer:contactHex sent:nil])) _card = [contactHex copy];
    return self;
}

- (void)loadView {
    [self mesh_loadScreen];
    CGFloat W = self.view.bounds.size.width;
    UIScrollView *page = [self mesh_addPageTitled:_card ? L(@"Share contact with…") : L(@"Send contact")];
    if (!_contacts.count) {
        UILabel *none = [MeshControls labelWithFrame:CGRectMake(30, 60, W - 60, 60) font:[MeshTheme previewFont] color:[MeshTheme muted]];
        none.text = L(@"No other contacts to share");
        none.textAlignment = NSTextAlignmentCenter;
        none.numberOfLines = 0;
        [page addSubview:none];
        return;
    }
    MeshSession *s = [MeshSession shared];
    for (NSUInteger i = 0; i < _contacts.count; i++) {
        UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
        row.frame = CGRectMake(0, 6 + i * kRow, W, kRow);
        row.tag = (NSInteger)i;
        row.showsTouchWhenHighlighted = YES;
        [row addTarget:self action:@selector(pick:) forControlEvents:UIControlEventTouchUpInside];
        MeshAvatarView *av = [[MeshAvatarView alloc] initWithFrame:CGRectMake(18, (kRow - kAvatar) / 2, kAvatar, kAvatar) source:MeshAvatarContact];
        av.pubkey = _contacts[i];
        av.userInteractionEnabled = NO;
        [row addSubview:av];
        UILabel *name = [MeshControls labelWithFrame:CGRectMake(18 + kAvatar + 14, 0, W - kAvatar - 50, kRow) font:[MeshTheme bodyFont] color:[MeshTheme ink]];
        name.text = [s displayNameFor:_contacts[i]];
        [row addSubview:name];
        [page addSubview:row];
    }
    page.contentSize = CGSizeMake(W, 12 + _contacts.count * kRow);
}

- (void)pick:(UIButton *)row {
    MeshSession *s = [MeshSession shared];
    if (_card) {
        NSString *to = _contacts[row.tag];
        if (![s sendContact:_card to:to]) { [MeshPopup info:L(@"Failed")]; return; }
        // Gleich in den Chat, in den geteilt wurde (die Karte steht dort schon)
        UINavigationController *nav = self.navigationController;
        [nav popToRootViewControllerAnimated:NO];
        [nav pushViewController:[[ChatViewController alloc] initWithPeer:to] animated:YES];
        return;
    }
    if (![s sendContact:_contacts[row.tag] to:_peer]) { [MeshPopup info:L(@"Failed")]; return; }
    if (_sent) _sent();
    [self.navigationController popViewControllerAnimated:YES];
}

@end
