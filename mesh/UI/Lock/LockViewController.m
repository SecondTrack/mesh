// Ziffernblock für den 6-stelligen Code (eigener Block statt System-Tastatur,
// damit der Code nicht in Tastatur-Caches landet): Schild, Titel, sechs Punkte, Fehlerzeile, 3×4-Tasten.
#import "LockViewController.h"
#import "MeshScreen.h"
#import "MeshTheme.h"
#import "MeshSession.h"
#import "MeshGlyphs.h"
#import "MeshPopup.h"
#import "MeshL10n.h"
#import "MeshFormat.h"
#import "MeshPageHeader.h"

@implementation LockViewController {
    NSMutableString *_pin;
    NSString *_first;          // erste Eingabe im Setup (zum Bestätigen)
    UILabel *_titleLabel;
    UILabel *_subtitleLabel;
    UILabel *_errorLabel;
    NSMutableArray *_dots;     // ein Punkt je Ziffer
    NSTimer *_waitTimer;       // Countdown während der Sperrzeit
    UIButton *_resetBtn;       // "Code vergessen?", nur beim Entsperren
    UIView *_shield;
}

// Maße des Sperrbildschirms (480 pt hoch, Statusleiste ausgeblendet). Von unten: "PIN vergessen?",
// Tastenfeld, Punkte. Darüber von den Punkten aufwärts: Fehlerzeile, Untertitel (nur beim Festlegen),
// Titel, Schild; ohne Untertitel rückt der Kopf nach unten, statt ein Loch zu lassen. Über und unter
// dem Tastenfeld derselbe sichtbare Abstand (die Schrift im Knopf sitzt mittig, daher kleiner).
static const CGFloat kShieldSize = 54, kShieldIcon = 30, kShieldGap = 6;
static const CGFloat kTitleHeight = 28, kSubtitleHeight = 34, kErrorHeight = 18, kDotsTop = 152;
static const CGFloat kDotSize = 13, kDotGap = 16;
static const CGFloat kKeySize = 58, kKeyGapX = 24, kKeyGapY = 8;
static const CGFloat kResetHeight = 26, kResetBottom = 7, kKeypadToReset = 10;

- (void)loadView {
    [self mesh_loadScreen];
    CGFloat W = self.view.bounds.size.width;
    _pin = [NSMutableString string];

    [self addShield];
    if (self.pageTitle) {   // Unterseite: Kopfzeile statt Schild
        _shield.hidden = YES;
        [self.view addSubview:[[MeshPageHeader alloc] initWithWidth:W title:self.pageTitle target:self back:@selector(mesh_goBack)]];
    }
    _titleLabel = [self centeredLabelAt:CGRectZero font:[MeshTheme titleFont] color:[MeshTheme ink]];
    _subtitleLabel = [self centeredLabelAt:CGRectZero font:[MeshTheme previewFont] color:[MeshTheme muted]];
    _subtitleLabel.numberOfLines = 2;
    _errorLabel = [self centeredLabelAt:CGRectZero font:[MeshTheme previewFont] color:[MeshTheme danger]];
    [self addDots];
    [self layoutHeader];

    _resetBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    CGFloat H = self.view.bounds.size.height;
    _resetBtn.frame = CGRectMake((W - 200) / 2, H - kResetBottom - kResetHeight, 200, kResetHeight);
    _resetBtn.titleLabel.font = [MeshTheme timeFont];
    NSString *resetTitle = self.verifyMode ? L(@"Cancel") : self.setupMode ? L(@"Choose other protection") : L(@"Forgot PIN?");
    [_resetBtn setTitle:resetTitle forState:UIControlStateNormal];
    [_resetBtn setTitleColor:[MeshTheme faint] forState:UIControlStateNormal];
    [_resetBtn addTarget:self action:@selector(tapReset) forControlEvents:UIControlEventTouchUpInside];
    _resetBtn.hidden = self.setupMode && !self.onBack;
    [self.view addSubview:_resetBtn];

    [self addKeypad];
    [self refreshTexts];
    [self updateWait];
}

- (UILabel *)centeredLabelAt:(CGRect)frame font:(UIFont *)font color:(UIColor *)color {
    UILabel *l = [[UILabel alloc] initWithFrame:frame];
    l.font = font;
    l.textColor = color;
    l.textAlignment = NSTextAlignmentCenter;
    l.backgroundColor = [UIColor clearColor];
    [self.view addSubview:l];
    return l;
}

// Von den Punkten aufwärts; hängt vom Modus ab, der nach "PIN vergessen?" wechselt.
- (void)layoutHeader {
    CGFloat W = self.view.bounds.size.width;
    CGFloat errorTop = kDotsTop - 4 - kErrorHeight;
    CGFloat subtitleTop = errorTop - 2 - kSubtitleHeight;
    CGFloat titleTop = (self.setupMode ? subtitleTop : errorTop) - 4 - kTitleHeight;
    _shield.frame = CGRectMake((W - kShieldSize) / 2, MAX(4, titleTop - kShieldGap - kShieldSize), kShieldSize, kShieldSize);
    _titleLabel.frame = CGRectMake(20, titleTop, W - 40, kTitleHeight);
    _subtitleLabel.frame = CGRectMake(24, subtitleTop, W - 48, kSubtitleHeight);
    _subtitleLabel.hidden = !self.setupMode;
    _errorLabel.frame = CGRectMake(20, errorTop, W - 40, kErrorHeight);
}

- (void)addShield {
    UIView *shield = [[UIView alloc] initWithFrame:CGRectMake(0, 0, kShieldSize, kShieldSize)];
    _shield = shield;
    shield.backgroundColor = [[MeshTheme accent] colorWithAlphaComponent:0.14f];
    shield.layer.cornerRadius = kShieldSize / 2;
    shield.layer.borderWidth = 1.5f;
    shield.layer.borderColor = [MeshTheme accent].CGColor;
    CGFloat inset = (kShieldSize - kShieldIcon) / 2;
    UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectMake(inset, inset, kShieldIcon, kShieldIcon)];
    icon.image = [MeshGlyphs icon:@"shield" color:[MeshTheme accent] size:kShieldIcon];
    [shield addSubview:icon];
    [self.view addSubview:shield];
}

// Ein Punkt je Ziffer.
- (void)addDots {
    CGFloat W = self.view.bounds.size.width;
    CGFloat total = MeshPinLength * kDotSize + (MeshPinLength - 1) * kDotGap, x0 = (W - total) / 2;
    _dots = [NSMutableArray array];
    for (int i = 0; i < MeshPinLength; i++) {
        UIView *dot = [[UIView alloc] initWithFrame:CGRectMake(x0 + i * (kDotSize + kDotGap), kDotsTop, kDotSize, kDotSize)];
        dot.layer.cornerRadius = kDotSize / 2;
        dot.layer.borderWidth = 1;
        dot.layer.borderColor = [MeshTheme line].CGColor;
        dot.backgroundColor = [MeshTheme field];
        [self.view addSubview:dot];
        [_dots addObject:dot];
    }
}

// 3×4-Tastenfeld über "PIN vergessen?" am unteren Rand.
- (void)addKeypad {
    CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height;
    CGFloat x0 = (W - (3 * kKeySize + 2 * kKeyGapX)) / 2;
    CGFloat y0 = H - kResetBottom - kResetHeight - kKeypadToReset - (4 * kKeySize + 3 * kKeyGapY);
    NSArray *rows = @[ @[@"1", @"2", @"3"], @[@"4", @"5", @"6"], @[@"7", @"8", @"9"], @[@"", @"0", @"<"] ];
    for (int r = 0; r < 4; r++) {
        for (int c = 0; c < 3; c++) {
            NSString *label = rows[r][c];
            if (!label.length) continue;
            UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
            b.frame = CGRectMake(x0 + c * (kKeySize + kKeyGapX), y0 + r * (kKeySize + kKeyGapY), kKeySize, kKeySize);
            b.backgroundColor = [MeshTheme surfaceHi];
            b.layer.cornerRadius = kKeySize / 2;
            if ([label isEqualToString:@"<"]) {
                [b setImage:[MeshGlyphs icon:@"back" color:[MeshTheme ink] size:24] forState:UIControlStateNormal];
                [b addTarget:self action:@selector(tapDelete) forControlEvents:UIControlEventTouchUpInside];
            } else {
                [b setTitle:label forState:UIControlStateNormal];
                [b setTitleColor:[MeshTheme ink] forState:UIControlStateNormal];
                b.titleLabel.font = [MeshTheme keypadFont];
                b.tag = [label integerValue] + 100;   // 100..109 = Ziffer 0..9
                [b addTarget:self action:@selector(tapDigit:) forControlEvents:UIControlEventTouchUpInside];
            }
            [self.view addSubview:b];
        }
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(discardInput)
                                                 name:UIApplicationWillResignActiveNotification object:nil];
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

// Halb eingegebene PIN verwerfen, wenn die App inaktiv wird; eine anstehende Prüfung entfällt.
- (void)discardInput {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(commit) object:nil];
    [_pin setString:@""];
    [self updateDots];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_waitTimer invalidate]; _waitTimer = nil;
}

// Sperrzeit nach zu vielen Fehlversuchen: Countdown anzeigen, Eingabe solange ignorieren.
- (void)updateWait {
    NSTimeInterval left = self.setupMode ? 0 : [[MeshSession shared] pinWaitRemaining];   // gilt auch beim Prüfen
    if (left <= 0) {
        if (_waitTimer) { _errorLabel.text = @""; [_waitTimer invalidate]; _waitTimer = nil; }
        return;
    }
    _errorLabel.text = [MeshFormat pinWait:left];
    if (!_waitTimer) _waitTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self
                                       selector:@selector(updateWait) userInfo:nil repeats:YES];
}

- (void)refreshTexts {
    if (self.setupMode) {
        _titleLabel.text = _first ? L(@"Repeat PIN") : self.chooseTitle ?: (self.onPinChosen ? L(@"New PIN") : L(@"Set a PIN"));
        _subtitleLabel.text = _first ? L(@"Enter again to confirm")
                            : self.chooseTitle ? LF(@"%d digits, not your real PIN", MeshPinLength)
                            : LF(@"%d digits — protects your key on this device", MeshPinLength);
    } else {
        _titleLabel.text = L(@"Enter PIN");
        _subtitleLabel.text = @"";
    }
}

- (void)updateDots {
    for (int i = 0; i < MeshPinLength; i++) {
        UIView *dot = _dots[i];
        BOOL on = i < (int)_pin.length;
        dot.backgroundColor = on ? [MeshTheme accent] : [MeshTheme field];
        dot.layer.borderWidth = on ? 0 : 1;
    }
}

- (void)tapDigit:(UIButton *)b {
    if (_pin.length >= MeshPinLength || _waitTimer) return;
    [_pin appendFormat:@"%ld", (long)(b.tag - 100)];
    _errorLabel.text = @"";
    [self updateDots];
    if (_pin.length == MeshPinLength) [self performSelector:@selector(commit) withObject:nil afterDelay:0.12];   // letzter Punkt sichtbar
}

- (void)tapDelete {
    if (_pin.length > 0) { [_pin deleteCharactersInRange:NSMakeRange(_pin.length-1,1)]; [self updateDots]; }
}

// Nur bei aktiver App: Wurde zwischen letzter Ziffer und Prüfung der Standby-Knopf gedrückt, darf
// nicht im Hintergrund entsperrt werden (es käme kein weiteres Sperr-Ereignis mehr).
- (void)commit {
    if ([UIApplication sharedApplication].applicationState != UIApplicationStateActive) { [self discardInput]; return; }
    NSString *p = [_pin copy];
    [_pin setString:@""]; [self updateDots];
    if (self.setupMode) {
        if (!_first) { _first = p; [self refreshTexts]; return; }        // erste Eingabe -> bestätigen
        if (![p isEqualToString:_first]) { _first = nil; [self refreshTexts]; _errorLabel.text = L(@"PINs don't match"); return; }
        MeshPinResult r = self.onPinChosen ? self.onPinChosen(p) : [[MeshSession shared] setupWithPin:p];
        if (r == MeshPinOK) { [self done]; return; }
        _first = nil; [self refreshTexts];
        _errorLabel.text = r == MeshPinFailed ? L(@"Setup failed") : [MeshFormat pinError:r wait:0];
    } else if (self.verifyMode) {
        MeshPinResult r = [[MeshSession shared] verifyPin:p];
        if (r == MeshPinOK) { if (self.onVerified) self.onVerified(p); return; }
        if (r != MeshPinWiped) _errorLabel.text = [MeshFormat pinError:r wait:[[MeshSession shared] pinWaitRemaining]];
        [self updateWait];
    } else {
        MeshPinResult r = [[MeshSession shared] unlockWithPin:p];
        if (r == MeshPinOK) { [self done]; return; }
        if (r == MeshPinWiped) { [self startOver]; return; }
        _errorLabel.text = [MeshFormat pinError:r wait:[[MeshSession shared] pinWaitRemaining]];
        [self updateWait];   // Countdown, falls jetzt gesperrt
    }
}

- (void)tapReset {
    if (self.verifyMode) { if (self.onCancel) self.onCancel(); }
    else if (self.setupMode) { if (self.onBack) self.onBack(); }
    else [self askReset];
}

// Zwei Bestätigungen: Danach ist die Identität ohne gesicherten nsec unwiederbringlich weg.
- (void)askReset {
    [MeshPopup confirm:L(@"Reset Mesh?")
               message:L(@"Without the PIN your key cannot be opened. Resetting deletes your key, all messages and contacts on this device. You start with a new identity.")
                action:L(@"Continue") destructive:YES handler:^(BOOL yes) {
        if (!yes) return;
        [MeshPopup confirm:L(@"Delete everything?") message:L(@"This cannot be undone.")
                    action:L(@"Delete") destructive:YES handler:^(BOOL sure) {
            if (!sure) return;
            [[MeshSession shared] resetEverything];
            [self startOver];
        }];
    }];
}

// Nach dem Löschen: wie beim ersten Start einrichten (normalerweise erst die Schutzart wählen).
- (void)startOver {
    if (self.onStartOver) { self.onStartOver(); return; }
    self.setupMode = YES;
    _first = nil;
    [_pin setString:@""];
    _resetBtn.hidden = YES;
    _errorLabel.text = @"";
    [self layoutHeader];
    [self updateDots];
    [self refreshTexts];
}

- (void)done {
    [_waitTimer invalidate]; _waitTimer = nil;
    if (self.onUnlocked) self.onUnlocked();
}

@end
