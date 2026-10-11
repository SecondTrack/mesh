#import "WordsSetupViewController.h"
#import "MeshScreen.h"
#import "MeshTheme.h"
#import "MeshControls.h"
#import "MeshPageHeader.h"
#import "MeshPassphrase.h"
#import "MeshFormat.h"
#import "MeshL10n.h"

// Maße unter der Kopfzeile (480 pt hoch). Bestätigen: alles über der Tastatur (ab 264 pt).
static const CGFloat kRowHeight = 30, kCardPad = 10, kButtonHeight = 44;

@implementation WordsSetupViewController {
    NSUInteger _count;
    NSString *_language;       // Sprache der Wörter (de/en), umschaltbar oben rechts
    UIButton *_languageBtn;
    NSArray *_words;
    UIView *_showPage, *_confirmPage, *_card;
    UITextField *_field;
    UILabel *_status;
    UIButton *_doneBtn, *_revealBtn;
}

- (instancetype)initWithWords:(NSUInteger)count {
    if ((self = [super init])) {
        _count = MAX(count, (NSUInteger)MeshPassphraseWords);
        _language = [MeshPassphrase defaultLanguage];
    }
    return self;
}

- (void)loadView {
    [self mesh_loadScreen];
    CGFloat W = self.view.bounds.size.width, top = [MeshPageHeader height];
    MeshPageHeader *header = [[MeshPageHeader alloc] initWithWidth:W title:LF(@"Your %d words", (int)_count) target:self back:@selector(back)];
    _languageBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    _languageBtn.frame = CGRectMake(W - 96, [MeshTheme topInset], 90, top - [MeshTheme topInset]);
    _languageBtn.titleLabel.font = [MeshTheme timeFont];
    _languageBtn.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
    [_languageBtn setTitleColor:[MeshTheme accent] forState:UIControlStateNormal];
    [_languageBtn addTarget:self action:@selector(switchLanguage) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:_languageBtn];
    [self.view addSubview:header];
    CGRect page = CGRectMake(0, top, W, self.view.bounds.size.height - top);
    _showPage = [[UIView alloc] initWithFrame:page];
    _confirmPage = [[UIView alloc] initWithFrame:page];
    _confirmPage.hidden = YES;
    [self.view addSubview:_showPage];
    [self.view addSubview:_confirmPage];
    [self buildShowPage];
    [self buildConfirmPage];
    [self roll];
}

- (void)buildShowPage {
    CGFloat W = _showPage.bounds.size.width, H = _showPage.bounds.size.height, y = 12;
    UILabel *intro = [MeshControls labelWithFrame:CGRectMake(20, y, W - 40, 46) font:[MeshTheme timeFont] color:[MeshTheme muted]];
    intro.text = L(@"Write these words down on paper, in this order. Without them nobody gets in, not even you. Never store them on a phone or computer.");
    intro.numberOfLines = 3;
    [_showPage addSubview:intro];
    y += 52;

    _card = [MeshControls cardWithFrame:CGRectMake(16, y, W - 32, _count * kRowHeight + 2 * kCardPad)];
    _card.backgroundColor = [MeshTheme surface];
    [_showPage addSubview:_card];
    y += _card.bounds.size.height + 6;

    UILabel *bits = [MeshControls labelWithFrame:CGRectMake(20, y, W - 40, 18) font:[MeshTheme monoFont] color:[MeshTheme faint]];
    bits.text = LF(@"≈ %d bit · each word 1 of 7776", (int)lround([MeshPassphrase bitsForWords:_count]));
    bits.textAlignment = NSTextAlignmentCenter;
    [_showPage addSubview:bits];

    CGFloat by = H - 14 - kButtonHeight;
    [_showPage addSubview:[MeshControls primaryButtonWithFrame:CGRectMake(16, by, W - 32, kButtonHeight)
                                                         title:L(@"Written down — continue") target:self action:@selector(showConfirm)]];
    by -= kButtonHeight + 10;
    [_showPage addSubview:[MeshControls secondaryButtonWithFrame:CGRectMake(16, by, W - 32, kButtonHeight)
                                                           title:L(@"New words") target:self action:@selector(roll)]];
}

- (void)buildConfirmPage {
    CGFloat W = _confirmPage.bounds.size.width, y = 12;
    UILabel *intro = [MeshControls labelWithFrame:CGRectMake(20, y, W - 40, 32) font:[MeshTheme timeFont] color:[MeshTheme muted]];
    intro.text = L(@"Type the words from your paper to check them, with spaces in between.");
    intro.numberOfLines = 2;
    [_confirmPage addSubview:intro];
    y += 38;

    _field = [MeshControls fieldWithFrame:CGRectMake(16, y, W - 32, kButtonHeight) placeholder:L(@"Words") mono:YES delegate:self];
    if ([_field respondsToSelector:@selector(setSpellCheckingType:)]) _field.spellCheckingType = UITextSpellCheckingTypeNo;   // ab iOS 5
    _field.secureTextEntry = YES;   // kein Tastatur-Lernwörterbuch, kein Mitlesen über die Schulter
    _field.returnKeyType = UIReturnKeyDone;
    _revealBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    _revealBtn.frame = CGRectMake(0, 0, 64, kButtonHeight);
    _revealBtn.titleLabel.font = [MeshTheme timeFont];
    [_revealBtn setTitleColor:[MeshTheme accent] forState:UIControlStateNormal];
    [_revealBtn setTitle:L(@"Show") forState:UIControlStateNormal];
    [_revealBtn addTarget:self action:@selector(toggleReveal) forControlEvents:UIControlEventTouchUpInside];
    _field.rightView = _revealBtn;
    _field.rightViewMode = UITextFieldViewModeAlways;
    [_confirmPage addSubview:_field];
    y += kButtonHeight + 6;

    _status = [MeshControls labelWithFrame:CGRectMake(20, y, W - 40, 18) font:[MeshTheme timeFont] color:[MeshTheme muted]];
    _status.textAlignment = NSTextAlignmentCenter;
    [_confirmPage addSubview:_status];
    y += 24;

    _doneBtn = [MeshControls primaryButtonWithFrame:CGRectMake(16, y, W - 32, kButtonHeight) title:L(@"Done") target:self action:@selector(confirm)];
    [_confirmPage addSubview:_doneBtn];
    y += kButtonHeight + 4;

    UIButton *again = [UIButton buttonWithType:UIButtonTypeCustom];
    again.frame = CGRectMake(16, y, W - 32, 30);
    again.titleLabel.font = [MeshTheme timeFont];
    [again setTitleColor:[MeshTheme faint] forState:UIControlStateNormal];
    [again setTitle:L(@"Show the words again") forState:UIControlStateNormal];
    [again addTarget:self action:@selector(showWords) forControlEvents:UIControlEventTouchUpInside];
    [_confirmPage addSubview:again];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(hideSecrets) name:UIApplicationWillResignActiveNotification object:nil];
    [nc addObserver:self selector:@selector(showSecrets) name:UIApplicationDidBecomeActiveNotification object:nil];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

// Das Bild im App-Umschalter landet als Datei auf dem Gerät: Wörter vorher verdecken.
- (void)hideSecrets { _card.hidden = YES; _field.text = @""; [self updateStatus]; }
- (void)showSecrets { _card.hidden = NO; }

#pragma mark - Wörter

- (void)roll {
    _words = [MeshPassphrase randomWords:_count language:_language];
    if (_words.count != _count) _words = nil;   // Liste nicht lesbar: dann gibt es nichts zu bestätigen (confirm prüft)
    // Knopf nennt die Sprache, zu der er wechselt.
    [_languageBtn setTitle:[_language isEqualToString:@"de"] ? @"English" : @"Deutsch" forState:UIControlStateNormal];
    for (UIView *v in [_card.subviews copy]) [v removeFromSuperview];
    CGFloat w = _card.bounds.size.width;
    for (NSUInteger i = 0; i < _words.count; i++) {
        CGFloat y = kCardPad + i * kRowHeight;
        UILabel *n = [MeshControls labelWithFrame:CGRectMake(14, y, 30, kRowHeight) font:[MeshTheme monoFont] color:[MeshTheme faint]];
        n.text = [NSString stringWithFormat:@"%lu", (unsigned long)i + 1];
        [_card addSubview:n];
        UILabel *word = [MeshControls labelWithFrame:CGRectMake(44, y, w - 58, kRowHeight) font:[MeshTheme monoBigFont] color:[MeshTheme ink]];
        word.text = _words[i];
        [_card addSubview:word];
    }
}

// Andere Sprache: neue Wörter aus deren Liste (gleich viele Bit).
- (void)switchLanguage {
    NSArray *langs = [MeshPassphrase languages];
    _language = langs[([langs indexOfObject:_language] + 1) % langs.count];
    [self roll];
}

- (NSString *)phrase { return [_words componentsJoinedByString:@" "]; }

#pragma mark - Seiten

- (void)showConfirm {
    _languageBtn.hidden = YES;   // die Wörter stehen fest
    _showPage.hidden = YES;
    _confirmPage.hidden = NO;
    _field.text = @"";
    [self updateStatus];
    [_field becomeFirstResponder];
}

- (void)showWords {
    [_field resignFirstResponder];
    _field.text = @"";
    _confirmPage.hidden = YES;
    _showPage.hidden = NO;
    _languageBtn.hidden = NO;
}

- (void)back {
    if (!_confirmPage.hidden) { [self showWords]; return; }
    if (self.onBack) self.onBack(); else [self mesh_goBack];
}

#pragma mark - Bestätigen

// Ein sicheres Feld leert sich sonst beim erneuten Tippen nach einem Fokuswechsel.
- (BOOL)textField:(UITextField *)tf shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)s {
    tf.text = [tf.text stringByReplacingCharactersInRange:range withString:s];
    [self updateStatus];
    return NO;
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf { [self confirm]; return NO; }

- (void)toggleReveal {
    NSString *text = _field.text;
    BOOL wasFirst = _field.isFirstResponder;
    if (wasFirst) [_field resignFirstResponder];
    _field.secureTextEntry = !_field.secureTextEntry;
    _field.text = text;
    _field.font = [MeshTheme monoFont];
    [_revealBtn setTitle:_field.secureTextEntry ? L(@"Show") : L(@"Hide") forState:UIControlStateNormal];
    if (wasFirst) [_field becomeFirstResponder];
}

// Zählt, wie viele der getippten Wörter in der Liste stehen (verrät nichts über die Reihenfolge).
- (void)updateStatus {
    NSString *n = [MeshPassphrase normalize:_field.text ?: @""];
    _status.textColor = [MeshTheme muted];
    _status.text = LF(@"%d of %d words recognised", (int)(n.length ? [MeshPassphrase knownWordsIn:n] : 0), (int)_count);
}

- (void)confirm {
    if (!_words.count) { _status.textColor = [MeshTheme danger]; _status.text = L(@"Setup failed"); return; }
    if (![[MeshPassphrase normalize:_field.text ?: @""] isEqualToString:[self phrase]]) {
        _status.textColor = [MeshTheme danger];
        _status.text = L(@"Doesn't match — check spelling and order");
        return;
    }
    [_field resignFirstResponder];
    _doneBtn.enabled = NO;
    _status.textColor = [MeshTheme muted];
    _status.text = L(@"Encrypting … takes a few seconds");
    [self performSelector:@selector(save) withObject:nil afterDelay:0.05];   // Text erst zeichnen, dann scrypt
}

- (void)save {
    MeshPinResult r = self.onConfirmed ? self.onConfirmed([self phrase]) : MeshPinFailed;
    _doneBtn.enabled = YES;
    if (r == MeshPinOK) return;
    _status.textColor = [MeshTheme danger];
    _status.text = r == MeshPinFailed ? L(@"Setup failed") : [MeshFormat pinError:r wait:0];
}

@end
