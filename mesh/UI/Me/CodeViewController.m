// Mein Code wie in der Android-App: ein Live-QR, der alle 10 s einen frischen Einmal-Schlüssel
// trägt (Forward Secrecy schon für die erste Nachricht). Der Rahmen läuft als Countdown ab, die
// Schlüssel-Plakette dreht sich bei jedem Wechsel. Ein gescannter Code bleibt gültig, bis er
// eingelöst ist (die letzten 720 Einmal-Schlüssel, siehe MeshSignal).
#import "CodeViewController.h"
#import <QuartzCore/QuartzCore.h>
#import "MeshScreen.h"
#import "MeshAvatarView.h"
#import "MeshTheme.h"
#import "MeshPageHeader.h"
#import "MeshSession.h"
#import "MeshQR.h"
#import "MeshL10n.h"
#import "MeshClipboard.h"
#import "MeshControls.h"
#import "MeshSplitCode.h"

static const NSTimeInterval kRefresh = 10;   // wie Android: nicht schneller, sonst verfällt ein Code vor dem Einlösen
static const CGFloat kRing = 5, kRingRadius = 26;

@implementation CodeViewController {
    UIImageView *_qr;
    UIButton *_badge;
    CAShapeLayer *_ring;
    NSTimer *_timer;
    CGFloat _qrSize;
    NSString *_code;             // gerade gezeigter Code (für die Vollbildansicht)
    UIView *_full;               // Vollbild-Code, solange offen
    CGFloat _brightness;         // Bildschirmhelligkeit vor der Vollbildansicht
    BOOL _single;                // ein voller Code (für Android) statt zwei Teilen (iPod ↔ iPod)
    NSInteger _part;             // gezeigter Teil (0 … MESH_SPLIT_PARTS-1) im geteilten Modus
    UILabel *_partBadge, *_hint;
    BOOL _frozen;
    UIImageView *_fullQR;        // Vollbild: Code (geteilt: aktueller Teil)
    UILabel *_fullLbl;           // Vollbild: "Teil 1 von 3"
    UIView *_wordsView;          // 4 Wörter für iPods ohne Kamera
    UILabel *_wordsLbl, *_wordsTime;
    NSDate *_wordsUntil;
    NSTimer *_wordsTimer;                // nach dem ersten Antippen bleibt der Code stehen (Teile passen in jeder Reihenfolge)
}

- (void)loadView {
    [self mesh_loadScreen];
    CGFloat W = self.view.bounds.size.width;

    MeshPageHeader *header = [[MeshPageHeader alloc] initWithWidth:W title:L(@"My Code") target:self back:@selector(mesh_goBack)];
    [self.view addSubview:header];

    CGFloat y = [MeshPageHeader height] + 10;
    MeshAvatarView *av = [[MeshAvatarView alloc] initWithFrame:CGRectMake((W - 68) / 2, y, 68, 68) source:MeshAvatarSelf];
    av.pubkey = [[MeshSession shared] myPubkeyHex] ?: @"";
    [self.view addSubview:av];
    _badge = [MeshAvatarView badgeWithGlyph:@"key" diameter:26 forAvatarFrame:av.frame];
    [self.view addSubview:_badge];
    y += 68 + 14;

    // QR in heller Karte, außen der Countdown-Rahmen
    CGFloat outer = W - 84, card = outer - 2 * (kRing + 4);
    UIView *frame = [[UIView alloc] initWithFrame:CGRectMake((W - outer) / 2, y, outer, outer)];
    CGRect ringRect = CGRectInset(frame.bounds, kRing / 2, kRing / 2);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:ringRect cornerRadius:kRingRadius];
    CAShapeLayer *track = [CAShapeLayer layer];
    track.path = path.CGPath;
    track.fillColor = [UIColor clearColor].CGColor;
    track.strokeColor = [[MeshTheme accent] colorWithAlphaComponent:0.15f].CGColor;
    track.lineWidth = kRing;
    [frame.layer addSublayer:track];
    _ring = [CAShapeLayer layer];
    _ring.path = path.CGPath;
    _ring.fillColor = [UIColor clearColor].CGColor;
    _ring.strokeColor = [MeshTheme accent].CGColor;
    _ring.lineWidth = kRing;
    _ring.lineCap = kCALineCapRound;
    [frame.layer addSublayer:_ring];

    UIView *cardV = [[UIView alloc] initWithFrame:CGRectMake((outer - card) / 2, (outer - card) / 2, card, card)];
    cardV.backgroundColor = [UIColor whiteColor];
    cardV.layer.cornerRadius = kRingRadius - 4;
    _qrSize = card - 24;
    _qr = [[UIImageView alloc] initWithFrame:CGRectMake(12, 12, _qrSize, _qrSize)];
    [cardV addSubview:_qr];
    [frame addSubview:cardV];
    [frame addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapCode)]];
    [self.view addSubview:frame];
    // Teil-Anzeige oben rechts auf dem Rahmen ("1/2")
    _partBadge = [MeshControls labelWithFrame:CGRectMake(frame.frame.origin.x + outer - 44, frame.frame.origin.y - 6, 44, 22) font:[MeshTheme timeFont] color:[UIColor blackColor]];
    _partBadge.textAlignment = NSTextAlignmentCenter; _partBadge.backgroundColor = [MeshTheme accent];
    _partBadge.layer.cornerRadius = 11; _partBadge.layer.masksToBounds = YES;
    [self.view addSubview:_partBadge];
    y += outer + 10;

    _single = YES;   // nur der Code, ohne Umschalten (geteilte Teile kann der Scanner weiter lesen)
    _hint = [MeshControls labelWithFrame:CGRectMake(12, y - 2, W - 24, 22) font:[MeshTheme timeFont] color:[MeshTheme muted]];
    _hint.textAlignment = NSTextAlignmentCenter; _hint.adjustsFontSizeToFitWidth = YES; _hint.minimumFontSize = 9;
    _hint.userInteractionEnabled = YES;
    [self.view addSubview:_hint];
    y += 28;

    CGFloat bw = (W - 56 - 10) / 2;
    [self.view addSubview:[MeshControls primaryButtonWithFrame:CGRectMake(28, y, bw, 46) title:L(@"Copy link") target:self action:@selector(tapCopy)]];
    [self.view addSubview:[MeshControls secondaryButtonWithFrame:CGRectMake(28 + bw + 10, y, bw, 46) title:L(@"4 words") target:self action:@selector(tapWords)]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _frozen = NO; _part = 0;
    [self refresh];
    _timer = [NSTimer scheduledTimerWithTimeInterval:kRefresh target:self selector:@selector(refresh) userInfo:nil repeats:YES];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stop) name:MeshWillLockNotification object:nil];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stop];
}

// Antippen: Code bildschirmfüllend, weiß, volle Helligkeit (größere Module für alte Kameras).
// Antippen schließt und stellt die Helligkeit wieder her.
- (void)showFull {
    if (_full || !_code) return;
    UIView *root = self.view.window ?: self.view;
    _full = [[UIView alloc] initWithFrame:root.bounds];
    _full.backgroundColor = [UIColor whiteColor];
    CGFloat side = root.bounds.size.width - 8;
    _fullQR = [[UIImageView alloc] initWithFrame:CGRectMake(4, (root.bounds.size.height - side) / 2, side, side)];
    [_full addSubview:_fullQR];
    _fullLbl = [[UILabel alloc] initWithFrame:CGRectMake(10, CGRectGetMaxY(_fullQR.frame) + 14, root.bounds.size.width - 20, 24)];
    _fullLbl.textAlignment = NSTextAlignmentCenter; _fullLbl.backgroundColor = [UIColor clearColor];
    _fullLbl.font = [UIFont boldSystemFontOfSize:17]; _fullLbl.textColor = [UIColor blackColor];
    [_full addSubview:_fullLbl];
    UIButton *x = [UIButton buttonWithType:UIButtonTypeCustom];
    x.frame = CGRectMake(root.bounds.size.width - 54, 14, 44, 44);
    [x setTitle:@"✕" forState:UIControlStateNormal]; [x setTitleColor:[UIColor colorWithWhite:0.35 alpha:1] forState:UIControlStateNormal];
    x.titleLabel.font = [UIFont systemFontOfSize:24];
    [x addTarget:self action:@selector(hideFull) forControlEvents:UIControlEventTouchUpInside];
    [_full addSubview:x];
    [_full addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(nextPart)]];
    [root addSubview:_full];
    [self drawCode];
    [_timer invalidate]; _timer = nil;   // der Code bleibt stehen, solange er gescannt wird
    UIScreen *screen = [UIScreen mainScreen];
    if ([screen respondsToSelector:@selector(setBrightness:)]) { _brightness = screen.brightness; screen.brightness = 1; }
}

- (void)hideFull {
    if (!_full) return;
    [_full removeFromSuperview];
    _full = nil; _fullQR = nil; _fullLbl = nil;
    UIScreen *screen = [UIScreen mainScreen];
    if ([screen respondsToSelector:@selector(setBrightness:)]) screen.brightness = _brightness;
    if (self.view.window) {
        [self refresh];
        _timer = [NSTimer scheduledTimerWithTimeInterval:kRefresh target:self selector:@selector(refresh) userInfo:nil repeats:YES];
    }
}

- (void)stop {
    [self hideFull];
    [self closeWords];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_timer invalidate]; _timer = nil;
    [_ring removeAllAnimations];
}

// Neuer Code mit frischem Einmal-Schlüssel, Plakette dreht sich, Rahmen läuft wieder voll ab.
// Geteilter Modus: Antippen wechselt zwischen Teil 1 und 2. Voller Code: Antippen vergrößert wie bisher.
// Antippen öffnet den Code im Vollbild (weiß, volle Helligkeit – so lesen alte Kameras am besten).
// Geteilt: im Vollbild schaltet jedes Tippen zum nächsten Teil, ✕ schließt.
- (void)tapCode {
    if (!_single && !_frozen) { _frozen = YES; [_ring removeAllAnimations]; _ring.strokeEnd = 1; }   // Code steht, Teile passen in jeder Reihenfolge
    [self showFull];
}
- (void)nextPart {
    if (_single) { [self hideFull]; return; }
    _part = (_part + 1) % MESH_SPLIT_PARTS;
    [self drawCode];
}
- (void)drawCode {
    if (!_code) return;
    NSString *s = _single ? _code : [MeshSplitCode partsOf:_code][_part];
    // Reines Schwarz auf Weiß: der stärkste Kontrast für alte Kameras ohne Autofokus.
    _qr.image = [MeshQR imageForString:s sizePx:_qrSize module:[UIColor blackColor] background:[UIColor whiteColor]];
    if (_fullQR) {
        _fullQR.image = [MeshQR imageForString:s sizePx:_fullQR.bounds.size.width module:[UIColor blackColor] background:[UIColor whiteColor]];
        _fullLbl.text = _single ? @"" : LF(@"Part %ld of %d · tap for next", (long)_part + 1, MESH_SPLIT_PARTS);
    }
    _partBadge.hidden = _single;
    _partBadge.text = [NSString stringWithFormat:@"%ld/%d", (long)_part + 1, MESH_SPLIT_PARTS];
    _hint.text = nil;
}

- (void)refresh {
    if (!_single && _frozen && _code) return;   // geteilt und schon durchgeblättert: gleicher Code, egal mit welchem Teil der Scanner anfängt
    NSString *code = [[MeshSession shared] myContactCode];
    if (!code) return;
    _code = code;
    [self drawCode];
    [UIView transitionWithView:_badge duration:0.5 options:UIViewAnimationOptionTransitionFlipFromLeft animations:nil completion:nil];
    CABasicAnimation *drain = [CABasicAnimation animationWithKeyPath:@"strokeEnd"];
    drain.fromValue = @1;
    drain.toValue = @0;
    drain.duration = kRefresh;
    drain.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    _ring.strokeEnd = 0;
    [_ring removeAllAnimations];
    [_ring addAnimation:drain forKey:@"countdown"];
}

// 4 Wörter: für Kontakte ohne Kamera, 10 Minuten gültig (MeshSession+Pairing)
- (void)tapWords {
    if (_wordsView) return;
    UIView *root = self.view.window ?: self.view;
    CGFloat W = root.bounds.size.width, H = root.bounds.size.height;
    _wordsView = [[UIView alloc] initWithFrame:root.bounds];
    _wordsView.backgroundColor = [MeshTheme bg];
    UILabel *t = [MeshControls labelWithFrame:CGRectMake(20, 60, W - 40, 22) font:[MeshTheme nameFont] color:[MeshTheme ink]];
    t.textAlignment = NSTextAlignmentCenter; t.text = L(@"Your 4 words");
    [_wordsView addSubview:t];
    _wordsLbl = [MeshControls labelWithFrame:CGRectMake(20, 110, W - 40, 190) font:[UIFont boldSystemFontOfSize:32] color:[MeshTheme accent]];
    _wordsLbl.textAlignment = NSTextAlignmentCenter; _wordsLbl.numberOfLines = 4; _wordsLbl.text = @"…";
    [_wordsView addSubview:_wordsLbl];
    _wordsTime = [MeshControls labelWithFrame:CGRectMake(20, 310, W - 40, 18) font:[MeshTheme timeFont] color:[MeshTheme muted]];
    _wordsTime.textAlignment = NSTextAlignmentCenter; _wordsTime.text = L(@"Creating …");
    [_wordsView addSubview:_wordsTime];
    UILabel *how = [MeshControls labelWithFrame:CGRectMake(24, 340, W - 48, 60) font:[MeshTheme timeFont] color:[MeshTheme muted]];
    how.textAlignment = NSTextAlignmentCenter; how.numberOfLines = 3;
    how.text = L(@"Your contact types them in Mesh: round button in the chat list → Add contact. Only one person can use them.");
    [_wordsView addSubview:how];
    [_wordsView addSubview:[MeshControls secondaryButtonWithFrame:CGRectMake(28, H - 76, W - 56, 46) title:L(@"Close") target:self action:@selector(closeWords)]];
    [root addSubview:_wordsView];
    __weak CodeViewController *ws = self;
    [[MeshSession shared] pairingWords:^(NSString *words, NSDate *expires, NSString *error) {
        CodeViewController *ss = ws; if (!ss || !ss->_wordsView) return;
        if (!words) { ss->_wordsLbl.text = @""; ss->_wordsTime.text = error; return; }
        ss->_wordsLbl.text = [words stringByReplacingOccurrencesOfString:@" " withString:@"\n"];
        ss->_wordsUntil = expires;
        [ss tickWords];
        ss->_wordsTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:ss selector:@selector(tickWords) userInfo:nil repeats:YES];
    }];
}
- (void)tickWords {
    NSTimeInterval left = [_wordsUntil timeIntervalSinceNow];
    if (left <= 0) { _wordsLbl.textColor = [MeshTheme muted]; _wordsTime.text = L(@"Expired – close and create new ones."); [_wordsTimer invalidate]; _wordsTimer = nil; return; }
    _wordsTime.text = LF(@"Valid for %d:%02d", (int)left / 60, (int)left % 60);
}
- (void)closeWords {
    [_wordsTimer invalidate]; _wordsTimer = nil;
    [_wordsView removeFromSuperview]; _wordsView = nil;
}

- (void)tapCopy {
    [MeshClipboard copyPublic:[[MeshSession shared] myStaticContactCode] confirmation:L(@"Link copied")];
}

@end
