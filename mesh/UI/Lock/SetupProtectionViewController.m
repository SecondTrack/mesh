#import "SetupProtectionViewController.h"
#import "MeshScreen.h"
#import "MeshTheme.h"
#import "MeshControls.h"
#import "MeshPassphrase.h"
#import "MeshL10n.h"
#import "MeshPageHeader.h"

// Maße (Bildschirm 480 pt hoch): Titel, Erklärung, drei Karten, Fußnote zur Annahme hinter den Zahlen.
static const CGFloat kTop = 16, kCardTop = 96, kCardHeight = 100, kCardGap = 10;
static const CGFloat kPageShift = 4;   // als Unterseite: Kopfzeile ersetzt den Titel, Karten rücken etwas tiefer

@implementation SetupProtectionViewController

- (void)loadView {
    [self mesh_loadScreen];
    CGFloat W = self.view.bounds.size.width;

    CGFloat shift = 0;
    if (self.pageTitle) {
        [self.view addSubview:[[MeshPageHeader alloc] initWithWidth:W title:self.pageTitle target:self back:@selector(mesh_goBack)]];
        shift = kPageShift;
    } else {
        UILabel *title = [MeshControls labelWithFrame:CGRectMake(20, kTop, W - 40, 28) font:[MeshTheme titleFont] color:[MeshTheme ink]];
        title.text = L(@"How should Mesh be protected?");
        title.adjustsFontSizeToFitWidth = YES;
        [self.view addSubview:title];
    }
    UILabel *intro = [MeshControls labelWithFrame:CGRectMake(20, kTop + 32 + shift, W - 40, 44) font:[MeshTheme timeFont] color:[MeshTheme muted]];
    intro.text = self.pageTitle ? L(@"Choose the new protection. Then you set the new PIN or get new words. Your chats stay.")
                                : L(@"Your key is locked with this. It matters when someone copies the data off this device. You can change it later under Security.");
    intro.numberOfLines = 3;
    [self.view addSubview:intro];

    // Zahlen: PIN 10^6 mit PBKDF2 (eine Grafikkarte, Sekunden); Wörter 7776^n mit scrypt
    // (1000 Grafikkarten zu je ~7000 Versuchen/s, im Mittel der halbe Raum).
    NSArray *cards = @[
        @[L(@"6-digit PIN"), @"", L(@"1 million combinations · cracked in seconds"), @YES,
          L(@"Quick to type. Safe only as long as nobody copies the device.")],
        @[LF(@"%d words", MeshPassphraseWords), L(@"RECOMMENDED"), LF(@"≈ %d bit · about 60,000 years*", (int)lround([MeshPassphrase bitsForWords:MeshPassphraseWords])), @NO,
          L(@"The app rolls random words for you to write down. Strong even against a copied device.")],
        @[LF(@"%d words", MeshPassphraseStrongWords), L(@"SAFEST"), LF(@"≈ %d bit · about 500 million years*", (int)lround([MeshPassphrase bitsForWords:MeshPassphraseStrongWords])), @NO,
          L(@"One word more makes it 7776 times harder. For high risk.")],
    ];
    for (NSUInteger i = 0; i < cards.count; i++)
        [self addCard:cards[i] tag:(NSInteger)i y:kCardTop + shift + i * (kCardHeight + kCardGap) width:W];

    CGFloat footTop = kCardTop + shift + 3 * (kCardHeight + kCardGap);
    UILabel *foot = [MeshControls labelWithFrame:CGRectMake(20, footTop, W - 40, self.view.bounds.size.height - footTop - 6) font:[MeshTheme timeFont] color:[MeshTheme faint]];
    foot.text = L(@"* with 1000 graphics cards, after copying the device. Without a copy the lock slows every guess down and deletes everything after 30 wrong tries.");
    foot.numberOfLines = 0;
    [self.view addSubview:foot];
}

// Karte als Knopf: Titel mit Abzeichen, Zahl, kurze Erklärung.
- (void)addCard:(NSArray *)c tag:(NSInteger)tag y:(CGFloat)y width:(CGFloat)W {
    UIButton *card = [UIButton buttonWithType:UIButtonTypeCustom];
    card.frame = CGRectMake(16, y, W - 32, kCardHeight);
    card.backgroundColor = [MeshTheme surface];
    card.layer.cornerRadius = [MeshTheme cardRadius];
    card.layer.borderWidth = 1;
    card.layer.borderColor = (tag == 1 ? [MeshTheme accentDim] : [MeshTheme line]).CGColor;
    card.tag = tag;
    [card addTarget:self action:@selector(choose:) forControlEvents:UIControlEventTouchUpInside];
    CGFloat inner = card.bounds.size.width - 28;

    UILabel *name = [MeshControls labelWithFrame:CGRectMake(14, 10, inner, 22) font:[MeshTheme nameFont] color:[MeshTheme ink]];
    name.text = c[0];
    [card addSubview:name];
    UILabel *badge = [MeshControls labelWithFrame:CGRectMake(14, 12, inner, 18) font:[MeshTheme labelFont] color:[MeshTheme accent]];
    badge.text = c[1];
    badge.textAlignment = NSTextAlignmentRight;
    [card addSubview:badge];
    UILabel *number = [MeshControls labelWithFrame:CGRectMake(14, 34, inner, 18) font:[MeshTheme monoFont]
                                             color:[c[3] boolValue] ? [MeshTheme danger] : [MeshTheme accent]];
    number.text = c[2];
    number.adjustsFontSizeToFitWidth = YES;
    [card addSubview:number];
    UILabel *text = [MeshControls labelWithFrame:CGRectMake(14, 54, inner, 38) font:[MeshTheme timeFont] color:[MeshTheme muted]];
    text.text = c[4];
    text.numberOfLines = 2;
    [card addSubview:text];
    for (UIView *v in card.subviews) v.userInteractionEnabled = NO;
    [self.view addSubview:card];
}

- (void)choose:(UIButton *)card {
    if (!self.onChoose) return;
    if (card.tag == 0) self.onChoose(MeshSecretPin, 0);
    else self.onChoose(MeshSecretWords, card.tag == 1 ? MeshPassphraseWords : MeshPassphraseStrongWords);
}

@end
