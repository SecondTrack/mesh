#import "PeerProfileViewController.h"
#import "MeshScreen.h"
#import "MeshAvatarView.h"
#import "MeshTheme.h"
#import "MeshPageHeader.h"
#import "MeshSession.h"
#import "MeshGlyphs.h"
#import "MeshImageViewer.h"
#import "MeshL10n.h"
#import "MeshFormat.h"
#import "MeshClipboard.h"
#import "MeshMenuRow.h"
#import "MeshPopup.h"
#import "MeshControls.h"

static const CGFloat kMargin = 16, kGap = 12, kAvatar = 104, kRowHeight = 54, kButtonWidth = 84;

@implementation PeerProfileViewController {
    NSString *_peerHex;
    UIButton *_vBtn;
    UILabel *_vLabel;
}
- (instancetype)initWithPeer:(NSString *)peerHex { if ((self = [super init])) _peerHex = [peerHex copy]; return self; }

// 12 Gruppen in drei Zeilen zu je vier; ohne Bundle des Kontakts gibt es noch keine.
- (NSString *)safetyNumber {
    NSArray *g = [[MeshSession shared] safetyNumberWith:_peerHex];
    if (!g) return nil;
    NSMutableArray *lines = [NSMutableArray array];
    for (NSUInteger i = 0; i + 4 <= g.count; i += 4)
        [lines addObject:[[g subarrayWithRange:NSMakeRange(i, 4)] componentsJoinedByString:@" "]];
    return [lines componentsJoinedByString:@"\n"];
}

- (void)loadView {
    [self mesh_loadScreen];
    CGFloat W = self.view.bounds.size.width;

    UIScrollView *sv = [self mesh_addPageTitled:L(@"Contact")];   // scrollbar: nie abgeschnitten

    CGFloat y = 20, inner = W - 2 * kMargin;
    MeshAvatarView *av = [[MeshAvatarView alloc] initWithFrame:CGRectMake((W - kAvatar) / 2, y, kAvatar, kAvatar) source:MeshAvatarContact];
    av.pubkey = _peerHex;
    av.userInteractionEnabled = YES;
    [av addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openAvatar)]];
    [sv addSubview:av];
    y += kAvatar + 14;

    UILabel *name = [MeshControls labelWithFrame:CGRectMake(20, y, W - 40, 28) font:[MeshTheme titleFont] color:[MeshTheme ink]];
    name.text = [MeshFormat contactName:[[MeshSession shared] displayNameFor:_peerHex] accepted:[[MeshSession shared] isAccepted:_peerHex]];
    name.textAlignment = NSTextAlignmentCenter;
    [sv addSubview:name];
    y += 40;

    // npub, antippen kopiert
    [sv addSubview:[MeshControls sectionLabelWithFrame:CGRectMake(18, y, W - 36, 14) text:@"NPUB"]];
    y += 20;
    UIView *card = [MeshControls cardWithFrame:CGRectMake(kMargin, y, inner, 56)];
    UILabel *npub = [MeshControls labelWithFrame:CGRectMake(12, 8, inner - 24, 40) font:[MeshTheme monoFont] color:[MeshTheme accent]];
    npub.text = [[MeshSession shared] npubFor:_peerHex];
    npub.numberOfLines = 0;
    [card addSubview:npub];
    UIButton *cardTap = [UIButton buttonWithType:UIButtonTypeCustom];
    cardTap.frame = card.bounds;
    [cardTap addTarget:self action:@selector(copyNpub) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:cardTap];
    [sv addSubview:card];
    y += 56 + kGap;

    // Verifizieren: Schild, Zustand, Knopf
    UIView *vrow = [MeshControls cardWithFrame:CGRectMake(kMargin, y, inner, kRowHeight)];
    UIImageView *shield = [[UIImageView alloc] initWithFrame:CGRectMake(14, (kRowHeight - 24) / 2, 24, 24)];
    shield.image = [MeshGlyphs icon:@"shield" color:[MeshTheme accent] size:24];
    [vrow addSubview:shield];
    _vLabel = [MeshControls labelWithFrame:CGRectMake(48, 0, inner - 48 - kButtonWidth - 18, kRowHeight) font:[MeshTheme bodyFont] color:[MeshTheme ink]];
    [vrow addSubview:_vLabel];
    _vBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    _vBtn.frame = CGRectMake(inner - kButtonWidth - 12, (kRowHeight - 30) / 2, kButtonWidth, 30);
    _vBtn.layer.cornerRadius = 15;
    _vBtn.titleLabel.font = [MeshTheme labelFont];
    [_vBtn addTarget:self action:@selector(toggleVerify) forControlEvents:UIControlEventTouchUpInside];
    [vrow addSubview:_vBtn];
    [sv addSubview:vrow];
    y += kRowHeight + kGap;
    [self updateVerify];

    // Verschlüsselung mit diesem Kontakt
    UILabel *crypto = [MeshControls labelWithFrame:CGRectMake(18, y, W - 36, 32) font:[MeshTheme timeFont] color:[MeshTheme muted]];
    crypto.numberOfLines = 2;
    crypto.text = [[MeshSession shared] usesSignalWith:_peerHex] ? L(@"Encrypted with Signal: each message has its own key (forward secrecy).")
                                                                 : L(@"Encrypted with NIP-44. Signal starts as soon as you have exchanged messages.");
    [sv addSubview:crypto];
    y += 40;

    // Sicherheitsnummer zum Vergleichen
    [sv addSubview:[MeshControls sectionLabelWithFrame:CGRectMake(18, y, W - 36, 14) text:L(@"SAFETY NUMBER")]];
    y += 20;
    NSString *number = [self safetyNumber];
    UILabel *num = [MeshControls labelWithFrame:CGRectMake(kMargin, y, inner, 80)
                                           font:number ? [MeshTheme monoBigFont] : [MeshTheme previewFont] color:[MeshTheme muted]];
    num.text = number ?: L(@"Appears as soon as you have exchanged messages. Only then can you verify.");
    num.numberOfLines = 0;
    num.textAlignment = NSTextAlignmentCenter;
    [sv addSubview:num];
    y += 90;

    // Notlöschung: löscht das Gerät des Kontakts, wenn er dieses Codewort bei sich gesetzt hat
    y = [MeshMenuRow addTo:sv y:y width:W icon:@"close" title:L(@"Send emergency wipe")
                  subtitle:L(@"Needs the codeword this contact has set") target:self action:@selector(sendWipe)];
    sv.contentSize = CGSizeMake(W, y + 20);
}

- (void)updateVerify {
    _vBtn.hidden = ![[MeshSession shared] safetyNumberWith:_peerHex];   // erst prüfbar mit Sicherheitsnummer
    BOOL v = [[MeshSession shared] isVerified:_peerHex];
    _vLabel.text = v ? L(@"Verified") : L(@"Not verified (TOFU)");
    [_vBtn setTitle:(v ? L(@"Unverify") : L(@"Verify")) forState:UIControlStateNormal];
    [_vBtn setTitleColor:(v ? [MeshTheme muted] : [MeshTheme bg]) forState:UIControlStateNormal];
    _vBtn.backgroundColor = v ? [MeshTheme surface] : [MeshTheme accent];
}
- (void)toggleVerify {
    [[MeshSession shared] setVerified:![[MeshSession shared] isVerified:_peerHex] for:_peerHex];
    [self updateVerify];
}
- (void)sendWipe {
    NSString *peer = _peerHex, *name = [[MeshSession shared] displayNameFor:_peerHex];
    [MeshPopup input:L(@"Send emergency wipe")
             message:LF(@"Deletes the device of %@ at once and for good, but only with the codeword %@ has set. Only a hash is sent; the codeword never leaves this device and is not stored.", name, name)
         placeholder:L(@"Codeword") secure:YES numeric:NO handler:^(NSString *text, BOOL ok) {
        if (!ok || ![text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length) return;
        [MeshPopup info:[[MeshSession shared] sendPanicTrigger:text to:peer] ? L(@"Emergency wipe sent") : L(@"Failed")];
    }];
}

- (void)copyNpub {
    [MeshClipboard copyPublic:[[MeshSession shared] npubFor:_peerHex] confirmation:L(@"npub copied")];
}
- (void)openAvatar {
    UIImage *big = [MeshAvatarView largeImageForSource:MeshAvatarContact pubkey:_peerHex];
    [self mesh_present:[[MeshImageViewer alloc] initWithImage:big] animated:YES];
}
@end
