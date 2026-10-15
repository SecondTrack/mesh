#import "PeerProfileViewController.h"
#import "MeshEmoji.h"
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
#import "MeshCompat.h"
#import "MeshText.h"
#import "MeshGalleryViewController.h"
#import "ContactPickerViewController.h"
#import "SafetyQRViewController.h"
#import "QRScannerViewController.h"
#import "MeshCaps.h"

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

    UILabel *name = [MeshControls userLabelWithFrame:CGRectMake(20, y, W - 40, 28) font:[MeshTheme titleFont] color:[MeshTheme ink]];
    name.text = [MeshFormat contactName:[[MeshSession shared] displayNameFor:_peerHex] accepted:[[MeshSession shared] isAccepted:_peerHex]];
    name.textAlignment = NSTextAlignmentCenter;
    [sv addSubview:name];
    y += 40;

    // "Über mich" aus dem Profil (wie Android)
    NSString *about = MeshStripInvisible([[MeshSession shared] aboutFor:_peerHex] ?: @"");
    if (about.length) {
        UILabel *a = [MeshControls userLabelWithFrame:CGRectZero font:[MeshTheme previewFont] color:[MeshTheme muted]];
        a.text = about;
        a.numberOfLines = 0;
        a.textAlignment = NSTextAlignmentCenter;
        CGSize sz = [MeshEmoji textSize:about font:a.font constrainedTo:CGSizeMake(W - 40, 200)];
        a.frame = CGRectMake(20, y - 6, W - 40, ceilf(sz.height));
        [sv addSubview:a];
        y += ceilf(sz.height) + 10;
    }

    // Medien des Chats und Kontakt weitergeben
    NSUInteger media = [MeshGalleryViewController countFor:_peerHex];
    if (media)
        y = [MeshMenuRow addTo:sv y:y width:W icon:@"gallery" title:L(@"Media")
                      subtitle:[MeshFormat media:media photosOnly:NO] target:self action:@selector(openMedia)];
    if ([[MeshSession shared] isAccepted:_peerHex])
        y = [MeshMenuRow addTo:sv y:y width:W icon:@"share" title:L(@"Share contact")
                      subtitle:L(@"Send this contact to someone else") target:self action:@selector(shareContact)];
    if (media || [[MeshSession shared] isAccepted:_peerHex]) y += kGap;

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

    // Statt Zahlen vorzulesen: einer zeigt den QR, der andere scannt ihn (wie Signal, gleiches Format wie Android)
    if (number) {
        BOOL cam = [MeshCaps hasCamera];
        CGFloat bw = cam ? (inner - 10) / 2 : inner;
        UIButton *show = [MeshControls secondaryButtonWithFrame:CGRectMake(kMargin, y, bw, 40) title:L(@"Show code") target:self action:@selector(showSafetyQR)];
        [MeshControls setIcon:[MeshGlyphs icon:@"shield" color:[MeshTheme ink] size:16] onButton:show];
        [sv addSubview:show];
        if (cam) {
            UIButton *scan = [MeshControls secondaryButtonWithFrame:CGRectMake(kMargin + bw + 10, y, bw, 40) title:L(@"Scan code") target:self action:@selector(scanSafetyQR)];
            [MeshControls setIcon:[MeshGlyphs icon:@"scan" color:[MeshTheme ink] size:16] onButton:scan];
            [sv addSubview:scan];
        }
        y += 50;
        UILabel *why = [MeshControls labelWithFrame:CGRectMake(18, y, W - 36, 64) font:[MeshTheme timeFont] color:[MeshTheme muted]];
        why.numberOfLines = 0;
        why.textAlignment = NSTextAlignmentCenter;
        why.text = L(@"Only needed if you didn't scan each other's Mesh codes directly, e.g. sent via Instagram or Telegram. Show each other the code and scan it – or compare the numbers in person or by call.");
        [why sizeToFit];
        why.frame = CGRectMake(18, y, W - 36, why.frame.size.height);
        [sv addSubview:why];
        y += why.frame.size.height + 16;
    }

    // Notlöschung: löscht das Gerät des Kontakts, wenn er dieses Codewort bei sich gesetzt hat
    y = [MeshMenuRow addTo:sv y:y width:W icon:@"close" title:L(@"Send emergency wipe")
                  subtitle:L(@"Needs the codeword this contact has set") target:self action:@selector(sendWipe)];
    y = [MeshMenuRow addTo:sv y:y width:W icon:@"block" title:L(@"Block contact")
                  subtitle:L(@"Delete and ignore future messages") target:self action:@selector(blockContact)];
    y = [MeshMenuRow addTo:sv y:y width:W icon:@"trash" title:L(@"Delete contact")
                  subtitle:L(@"Removes the contact and the whole chat") target:self action:@selector(deleteContact)];
    sv.contentSize = CGSizeMake(W, y + 20);
}

- (void)updateVerify {
    _vBtn.hidden = ![[MeshSession shared] safetyNumberWith:_peerHex];   // erst prüfbar mit Sicherheitsnummer
    BOOL v = [[MeshSession shared] isVerified:_peerHex];
    _vLabel.text = v ? L(@"Verified") : L(@"Not verified yet");
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

- (void)showSafetyQR {
    NSString *payload = [[MeshSession shared] safetyCodeQRWith:_peerHex];
    if (!payload) return;
    [self.navigationController pushViewController:[[SafetyQRViewController alloc] initWithPayload:payload
                                                                                          peerName:[[MeshSession shared] displayNameFor:_peerHex]] animated:YES];
}

- (void)scanSafetyQR {
    QRScannerViewController *sc = [[QRScannerViewController alloc] init];
    NSString *peer = _peerHex;
    MESH_WEAK PeerProfileViewController *weakSelf = self;
    sc.onScan = ^(NSString *payload) {
        NSString *name = [[MeshSession shared] displayNameFor:peer];
        switch ([[MeshSession shared] checkSafetyScan:payload with:peer]) {
            case MeshSafetyMatch:
                [MeshPopup info:LF(@"The safety codes match. %@ is now verified.", name)];
                break;
            case MeshSafetyMismatch:
                [MeshPopup confirm:L(@"Codes do NOT match")
                           message:L(@"Someone may be sitting between you and reading along. Don't write anything confidential until you have exchanged your Mesh codes again in person.")
                            action:L(@"OK") destructive:YES handler:nil];
                break;
            case MeshSafetyOtherContact:
                [MeshPopup info:LF(@"This code belongs to another chat. Scan the safety code that %@ shows in their profile of you.", name)];
                break;
            case MeshSafetyNotACode:
                [MeshPopup info:L(@"This is not a Mesh safety code.")];
                break;
        }
        [weakSelf updateVerify];
    };
    [self mesh_present:sc animated:YES];
}

- (void)openMedia {
    [self.navigationController pushViewController:[[MeshGalleryViewController alloc] initWithPeer:_peerHex] animated:YES];
}

- (void)shareContact {
    [self.navigationController pushViewController:[[ContactPickerViewController alloc] initSharingContact:_peerHex] animated:YES];
}

- (void)blockContact {
    NSString *peer = _peerHex;
    MESH_WEAK PeerProfileViewController *weakSelf = self;
    [MeshPopup confirm:L(@"Block contact?") message:L(@"The contact and the chat are deleted on this device. New messages from this key are ignored.")
                action:L(@"Block") destructive:YES handler:^(BOOL yes) {
        if (!yes) return;
        [[MeshSession shared] blockContact:peer];
        [weakSelf.navigationController popToRootViewControllerAnimated:YES];
    }];
}

- (void)deleteContact {
    NSString *peer = _peerHex;
    MESH_WEAK PeerProfileViewController *weakSelf = self;
    [MeshPopup confirm:L(@"Delete contact?") message:L(@"The contact and the whole chat are deleted on this device. The other person is not informed.")
                action:L(@"Delete") destructive:YES handler:^(BOOL yes) {
        if (!yes) return;
        [[MeshSession shared] deleteChat:peer];
        [weakSelf.navigationController popToRootViewControllerAnimated:YES];
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
