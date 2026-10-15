#import "IdentitiesViewController.h"
#import "MeshScreen.h"
#import "MeshPageHeader.h"
#import "MeshAvatarView.h"
#import "MeshMenuRow.h"
#import "MeshControls.h"
#import "MeshTheme.h"
#import "MeshSession.h"
#import "MeshIdentityInfo.h"
#import "MeshPopup.h"
#import "MeshSecretPrompt.h"
#import "MeshL10n.h"

static const CGFloat kAvatar = 58, kItem = 74, kRowHeight = 96;

@implementation IdentitiesViewController {
    UIScrollView *_row;
    NSString *_secret;   // beim Öffnen bestätigter Code: Anlegen fragt nicht noch einmal
}

- (instancetype)initWithSecret:(NSString *)secret {
    if ((self = [super init])) _secret = [secret copy];
    return self;
}

// Den Code nur halten, solange die Seite offen ist (Sperren ersetzt sie ohnehin).
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (![self.navigationController.viewControllers containsObject:self]) _secret = nil;
}

- (void)loadView {
    [self mesh_loadScreen];
    CGFloat W = self.view.bounds.size.width;
    UIScrollView *page = [self mesh_addPageTitled:L(@"Identities")];
    CGFloat y = 14;
    [page addSubview:[MeshControls sectionLabelWithFrame:CGRectMake(18, y, W - 36, 14) text:L(@"SWITCH OR ADD")]];
    y += 22;
    _row = [[UIScrollView alloc] initWithFrame:CGRectMake(0, y, W, kRowHeight)];
    _row.showsHorizontalScrollIndicator = NO;
    [page addSubview:_row];
    y += kRowHeight + 8;

    y = [MeshMenuRow addTo:page y:y width:W icon:@"key" title:L(@"Import with nsec") subtitle:L(@"Add an existing identity")
                    target:self action:@selector(importNsec)];

    // Gemeinsamer Posteingang
    [page addSubview:[MeshControls switchCardWithFrame:CGRectMake(16, y + 12, W - 32, 64) title:L(@"Unified inbox")
                                              subtitle:L(@"Chats of all identities in one list") on:[MeshSession shared].unifiedInbox
                                                target:self action:@selector(toggleUnified:)]];
    page.contentSize = CGSizeMake(W, y + 90);
    [self reloadRow];
}

// Kreise aller Identitäten (die angezeigte umrandet), dahinter "Neu".
- (void)reloadRow {
    for (UIView *v in _row.subviews) [v removeFromSuperview];
    NSArray *ids = [[MeshSession shared] identities];
    CGFloat x = 12;
    for (MeshIdentityInfo *i in ids) {
        [self addItemAt:x title:i.name.length ? i.name : [i.pubkey substringToIndex:MIN(8, i.pubkey.length)]
                 pubkey:i.pubkey picture:i.picture active:i.active tag:i.slot];
        x += kItem;
    }
    [self addItemAt:x title:L(@"New") pubkey:nil picture:nil active:NO tag:-1];
    _row.contentSize = CGSizeMake(x + kItem + 12, kRowHeight);
}

- (void)addItemAt:(CGFloat)x title:(NSString *)title pubkey:(NSString *)pubkey picture:(NSString *)picture active:(BOOL)active tag:(int)tag {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = CGRectMake(x, 0, kItem, kRowHeight);
    b.tag = tag;
    [b addTarget:self action:@selector(tapItem:) forControlEvents:UIControlEventTouchUpInside];
    CGFloat ax = (kItem - kAvatar) / 2;
    if (pubkey) {
        MeshAvatarView *av = [[MeshAvatarView alloc] initWithFrame:CGRectMake(ax, 4, kAvatar, kAvatar) source:MeshAvatarIdenticon];
        av.pubkey = pubkey;
        av.picture = picture;
        av.userInteractionEnabled = NO;
        if (active) { av.layer.borderWidth = 2.5f; av.layer.borderColor = [MeshTheme accent].CGColor; }
        [b addSubview:av];
    } else {
        UIView *plus = [[UIView alloc] initWithFrame:CGRectMake(ax, 4, kAvatar, kAvatar)];
        plus.backgroundColor = [MeshTheme surfaceHi];
        plus.layer.cornerRadius = kAvatar / 2;
        plus.userInteractionEnabled = NO;
        UILabel *p = [MeshControls labelWithFrame:plus.bounds font:[UIFont systemFontOfSize:30] color:[MeshTheme accent]];
        p.text = @"+";
        p.textAlignment = NSTextAlignmentCenter;
        [plus addSubview:p];
        [b addSubview:plus];
    }
    UILabel *name = [MeshControls userLabelWithFrame:CGRectMake(2, kAvatar + 10, kItem - 4, 16) font:[MeshTheme timeFont]
                                           color:active ? [MeshTheme accent] : [MeshTheme muted]];
    name.text = title;
    name.textAlignment = NSTextAlignmentCenter;
    [b addSubview:name];
    [_row addSubview:b];
}

- (void)tapItem:(UIButton *)b {
    if (b.tag >= 0) { [[MeshSession shared] switchToIdentity:(int)b.tag]; [self reloadRow]; return; }
    [MeshPopup confirm:L(@"New identity")
               message:L(@"A second identity with its own key, contacts and chats. It uses the same PIN and receives in the background.")
                action:L(@"Create") destructive:NO handler:^(BOOL yes) {
        if (yes) [self askPinThen:^(NSString *pin) { return [[MeshSession shared] addIdentityWithPin:pin nsec:nil]; } failure:L(@"Failed")];
    }];
}

// Die neue Identität wird mit dem Code verschlüsselt: der beim Öffnen bestätigte, sonst neu abfragen.
- (void)askPinThen:(BOOL (^)(NSString *pin))add failure:(NSString *)failure {
    void (^withSecret)(NSString *) = ^(NSString *pin) {
        if (!add(pin)) [MeshPopup info:failure];
        else if ([MeshSession shared].panicCodewordNeedsRenewal) [MeshPopup info:L(@"Set the emergency-wipe codeword again so that it also covers the new identity.")];
        [self reloadRow];
    };
    if (_secret) withSecret(_secret);
    else [MeshSecretPrompt verifyFrom:self then:withSecret];
}

- (void)importNsec {
    [MeshPopup input:L(@"Import with nsec") message:L(@"The secret key of an existing identity (nsec1…).")
         placeholder:@"nsec1…" secure:YES numeric:NO handler:^(NSString *text, BOOL ok) {
        if (!ok || !text.length) return;
        [self askPinThen:^(NSString *pin) { return [[MeshSession shared] addIdentityWithPin:pin nsec:text]; }
                 failure:L(@"Wrong PIN, not a valid nsec, or this identity is already here.")];
    }];
}

- (void)toggleUnified:(UISwitch *)sw { [MeshSession shared].unifiedInbox = sw.on; }

@end
