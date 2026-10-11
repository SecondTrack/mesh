// "Ich": Profilbild, Name, Beschreibung und die Einstellungen
// (Profil bearbeiten, Mein Code, Sicherheit, Ton).
#import "MeInViewController.h"
#import "MeshScreen.h"
#import "MeshAvatarView.h"
#import "MeshMenuRow.h"
#import "MeshTabBar.h"
#import "MeshTopBar.h"
#import "MeshCaps.h"
#import "MeshTheme.h"
#import "MeshSession.h"
#import "CodeViewController.h"
#import "ProfileEditViewController.h"
#import "SecurityViewController.h"
#import "AudioSettingsViewController.h"
#import "MeshImageViewer.h"
#import "MeshL10n.h"
#import "MeshProfile.h"
#import "MeshPopup.h"
#import "MeshSecretPrompt.h"
#import "MeshFormat.h"
#import "IdentitiesViewController.h"

@implementation MeInViewController {
    UILabel *_nameL;
    UILabel *_aboutL;
    MeshAvatarView *_avatar;
}

- (void)loadView {
    [self mesh_loadScreen];
    CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height;
    CGFloat headH = [MeshTopBar height], barH = [MeshTabBar height];
    NSString *pk = [[MeshSession shared] myPubkeyHex] ?: @"";

    [self.view addSubview:[[MeshTopBar alloc] initWithWidth:W title:L(@"Me") subtitle:L(@"Profile & Settings")]];

    // Scroll-Inhalt
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, headH, W, H - headH - barH)];
    scroll.backgroundColor = [MeshTheme bg];
    [self.view addSubview:scroll];

    CGFloat y = 22;
    // Avatar mit Kamera-Plakette
    _avatar = [[MeshAvatarView alloc] initWithFrame:CGRectMake((W-112)/2, y, 112, 112) source:MeshAvatarSelf];
    _avatar.pubkey = pk;
    [scroll addSubview:_avatar];
    [scroll addSubview:[MeshAvatarView badgeWithGlyph:@"camera" diameter:38 forAvatarFrame:_avatar.frame]];
    // Tippen auf den Avatar -> eigenes Bild groß (Bearbeiten über die Zeile „Profil bearbeiten").
    UIButton *avTap = [UIButton buttonWithType:UIButtonTypeCustom];
    avTap.frame = CGRectMake((W-112)/2, y, 112, 112);
    [avTap addTarget:self action:@selector(openSelfAvatar) forControlEvents:UIControlEventTouchUpInside];
    [scroll addSubview:avTap];
    y += 112 + 12;

    _nameL = [[UILabel alloc] initWithFrame:CGRectMake(20, y, W-40, 26)];
    _nameL.font = [MeshTheme titleFont]; _nameL.textColor = [MeshTheme ink];
    _nameL.textAlignment = NSTextAlignmentCenter; _nameL.backgroundColor = [UIColor clearColor]; [scroll addSubview:_nameL];
    y += 29;
    _aboutL = [[UILabel alloc] initWithFrame:CGRectMake(30, y, W-60, 18)];
    _aboutL.font = [MeshTheme previewFont]; _aboutL.textAlignment = NSTextAlignmentCenter;
    _aboutL.backgroundColor = [UIColor clearColor]; [scroll addSubview:_aboutL];
    y += 34;
    [self refreshProfile];

    y = [MeshMenuRow addTo:scroll y:y width:W icon:@"camera" title:L(@"Edit profile") subtitle:L(@"Name, picture, about") target:self action:@selector(openProfile)];
    y = [MeshMenuRow addTo:scroll y:y width:W icon:@"scan" title:L(@"My Code") subtitle:L(@"QR to share & scan") target:self action:@selector(openCode)];
    y = [MeshMenuRow addTo:scroll y:y width:W icon:@"shield" title:L(@"Security") subtitle:L(@"PIN, keys") target:self action:@selector(openSecurity)];
    y = [MeshMenuRow addTo:scroll y:y width:W icon:@"key" title:L(@"Identities") subtitle:L(@"Switch or add") target:self action:@selector(openIdentities)];
    if ([MeshCaps hasMicrophone])
        y = [MeshMenuRow addTo:scroll y:y width:W icon:@"mic" title:L(@"Sound & Microphone") subtitle:L(@"Gain, voice effect") target:self action:@selector(openAudio)];
    y += 30;
    scroll.contentSize = CGSizeMake(W, y);

    MeshTabBar *bar = [[MeshTabBar alloc] initWithFrame:CGRectMake(0, H - barH, W, barH) selected:MeshTabMe];
    MESH_WEAK MeInViewController *weakSelf = self;
    bar.onSelect = ^(MeshTab tab) { [weakSelf goChats]; };
    [self.view addSubview:bar];
}

- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self refreshProfile]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refreshProfile)
                                                 name:MeshIdentityChangedNotification object:nil];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

// Hinter einer erneuten PIN: weitere Identitäten bleiben sonst verborgen (wie Android).
- (void)openIdentities {
    [MeshSecretPrompt verifyFrom:self then:^(NSString *secret) {
        [self.navigationController pushViewController:[[IdentitiesViewController alloc] initWithSecret:secret] animated:YES];
    }];
}

- (void)refreshProfile {
    _avatar.pubkey = [[MeshSession shared] myPubkeyHex] ?: @"";
    MeshProfile *p = [[MeshSession shared] profile];
    NSString *nm = p.name, *ab = p.about;
    _nameL.text = nm.length ? nm : L(@"Your name");
    _aboutL.text = ab.length ? ab : L(@"Add a description");
    _aboutL.textColor = ab.length ? [MeshTheme muted] : [MeshTheme faint];
}

- (void)openProfile { [self.navigationController pushViewController:[[ProfileEditViewController alloc] init] animated:YES]; }
- (void)openCode { [self.navigationController pushViewController:[[CodeViewController alloc] init] animated:YES]; }
- (void)openSecurity { [self.navigationController pushViewController:[[SecurityViewController alloc] init] animated:YES]; }
- (void)openAudio { [self.navigationController pushViewController:[[AudioSettingsViewController alloc] init] animated:YES]; }
- (void)openSelfAvatar {
    UIImage *big = [MeshAvatarView largeImageForSource:MeshAvatarSelf pubkey:[[MeshSession shared] myPubkeyHex]];
    [self mesh_present:[[MeshImageViewer alloc] initWithImage:big] animated:YES];
}
- (void)goChats  { [self.navigationController popViewControllerAnimated:YES]; }

@end
