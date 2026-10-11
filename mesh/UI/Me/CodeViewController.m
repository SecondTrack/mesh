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
    [frame addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(showFull)]];
    [self.view addSubview:frame];
    y += outer + 10;

    UILabel *hint = [MeshControls labelWithFrame:CGRectMake(20, y, W - 40, 18) font:[MeshTheme timeFont] color:[MeshTheme muted]];
    hint.textAlignment = NSTextAlignmentCenter;
    hint.text = L(@"Only one person per code · tap to enlarge");
    [self.view addSubview:hint];
    y += 28;

    [self.view addSubview:[MeshControls primaryButtonWithFrame:CGRectMake(28, y, W - 56, 46) title:L(@"Copy link") target:self action:@selector(tapCopy)]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
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
    UIImageView *qr = [[UIImageView alloc] initWithFrame:CGRectMake(4, (root.bounds.size.height - side) / 2, side, side)];
    qr.image = [MeshQR imageForString:_code sizePx:side module:[UIColor blackColor] background:[UIColor whiteColor]];
    [_full addSubview:qr];
    [_full addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hideFull)]];
    [root addSubview:_full];
    [_timer invalidate]; _timer = nil;   // der Code bleibt stehen, solange er gescannt wird
    UIScreen *screen = [UIScreen mainScreen];
    if ([screen respondsToSelector:@selector(setBrightness:)]) { _brightness = screen.brightness; screen.brightness = 1; }
}

- (void)hideFull {
    if (!_full) return;
    [_full removeFromSuperview];
    _full = nil;
    UIScreen *screen = [UIScreen mainScreen];
    if ([screen respondsToSelector:@selector(setBrightness:)]) screen.brightness = _brightness;
    if (self.view.window) {
        [self refresh];
        _timer = [NSTimer scheduledTimerWithTimeInterval:kRefresh target:self selector:@selector(refresh) userInfo:nil repeats:YES];
    }
}

- (void)stop {
    [self hideFull];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_timer invalidate]; _timer = nil;
    [_ring removeAllAnimations];
}

// Neuer Code mit frischem Einmal-Schlüssel, Plakette dreht sich, Rahmen läuft wieder voll ab.
- (void)refresh {
    NSString *code = [[MeshSession shared] myContactCode];
    if (!code) return;
    _code = code;
    // Reines Schwarz auf Weiß: der stärkste Kontrast für alte Kameras ohne Autofokus.
    _qr.image = [MeshQR imageForString:code sizePx:_qrSize module:[UIColor blackColor] background:[UIColor whiteColor]];
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

- (void)tapCopy {
    [MeshClipboard copyPublic:[[MeshSession shared] myStaticContactCode] confirmation:L(@"Link copied")];
}

@end
