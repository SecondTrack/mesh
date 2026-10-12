// Mittelknoten mit pulsierenden Ringen, ein Knoten je Relay.
// Ein Relay-Knoten leuchtet auf, sobald dieses Relay wirklich verbunden ist; der Text sagt
// nur "über Tor", wenn Tor tatsächlich aktiv ist. Weiter, sobald ein Relay steht
// (kurz verzögert, damit man es sieht), per Tippen, oder wenn kTimeout lang nichts vorangeht
// (Tor-Fortschritt und Relays zählen als Fortschritt; beim allerersten Start lädt Tor das Verzeichnis
// des Netzes, am iPod 3–4 Minuten mit teils halbminütigen Pausen zwischen zwei Schritten).
#import "ConnectViewController.h"
#import "MeshScreen.h"
#import <QuartzCore/QuartzCore.h>
#import "MeshTheme.h"
#import "MeshGlyphs.h"
#import "MeshSession.h"
#import "MeshL10n.h"
#import "MeshCompat.h"

static const NSTimeInterval kTimeout = 45, kShowConnected = 0.8, kShowFailed = 2.5;
static const CGFloat kOrbit = 92, kNode = 14;
static const CGFloat kCore = 44, kCoreGap = 6;   // Schild in der Mitte; Linien enden kCoreGap davor

@implementation ConnectViewController {
    UIView *_stage;            // Animationsfläche, Mittelpunkt = Mittelknoten
    NSMutableArray *_nodes;    // CAShapeLayer je Relay
    NSMutableArray *_links;    // Verbindungslinien je Relay
    UILabel *_status, *_count, *_first;   // _first: Hinweis beim allerersten Tor-Start
    UIImageView *_onion;       // Tor-Zwiebel hinter dem Statustext
    NSTimer *_tick;            // zählt die Prozente weich hoch (10 × je Sekunde)
    float _shown;              // angezeigter Fortschritt 0…100
    BOOL _finished;
    BOOL _firstStart;          // beim Öffnen noch kein Tor-Verzeichnis da (einmal prüfen, nicht bei jedem Tick)
    int _progress;             // zuletzt gesehener Fortschritt (Tor-Prozent, Relays); -1 = noch keiner
}

- (void)loadView {
    [self mesh_loadScreen];
    CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height;

    UIImageView *logo = [[UIImageView alloc] initWithFrame:CGRectMake((W - 84) / 2, 40, 84, 84)];
    logo.image = [MeshGlyphs logo:84];
    [self.view addSubview:logo];
    [self addLabel:@"Mesh" font:[MeshTheme brandFont] color:[MeshTheme ink] y:132 height:32];
    [self addLabel:L(@"Your secure messenger") font:[MeshTheme previewFont] color:[MeshTheme muted] y:164 height:20];

    CGFloat stageY = 200, stageH = H - stageY - 96;
    _stage = [[UIView alloc] initWithFrame:CGRectMake(0, stageY, W, stageH)];
    [self.view addSubview:_stage];
    [self buildNetwork];

    _status = [self addLabel:@"" font:[MeshTheme nameFont] color:[MeshTheme ink] y:H - 84 height:22];
    _count  = [self addLabel:@"" font:[MeshTheme timeFont] color:[MeshTheme faint] y:H - 60 height:16];
    // Beim ersten Start lädt Tor erst das Netz-Verzeichnis (mehrere MB) – am iPod dauert das Minuten.
    _first = [self addLabel:L(@"First start: Tor is downloading the network once – this can take a few minutes.") font:[MeshTheme timeFont] color:[MeshTheme muted] y:H - 42 height:32];
    _first.numberOfLines = 2; _first.hidden = YES;
    _firstStart = [MeshSession shared].torFirstStart;
    _onion = [[UIImageView alloc] initWithImage:[MeshGlyphs icon:@"onion" color:[MeshTheme accent] size:18]];
    _onion.hidden = YES;
    [self.view addSubview:_onion];

    [self.view addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(finish)]];
}

- (UILabel *)addLabel:(NSString *)text font:(UIFont *)font color:(UIColor *)color y:(CGFloat)y height:(CGFloat)h {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(20, y, self.view.bounds.size.width - 40, h)];
    l.text = text; l.font = font; l.textColor = color;
    l.textAlignment = NSTextAlignmentCenter; l.backgroundColor = [UIColor clearColor];
    [self.view addSubview:l];
    return l;
}

static CAShapeLayer *circleLayer(CGPoint c, CGFloat r, UIColor *fill, UIColor *stroke) {
    CAShapeLayer *s = [CAShapeLayer layer];
    s.path = [UIBezierPath bezierPathWithArcCenter:CGPointZero radius:r startAngle:0 endAngle:2 * M_PI clockwise:YES].CGPath;
    s.position = c;
    s.fillColor = fill.CGColor;
    s.strokeColor = stroke.CGColor;
    s.lineWidth = 1.5f;
    return s;
}

- (void)buildNetwork {
    CGPoint c = CGPointMake(_stage.bounds.size.width / 2, _stage.bounds.size.height / 2);
    NSUInteger n = MAX([MeshSession shared].relayCount, (NSUInteger)1);
    _nodes = [NSMutableArray array]; _links = [NSMutableArray array];

    // Pulsierende Ringe um den Mittelknoten (zeitversetzt).
    for (int i = 0; i < 3; i++) {
        CAShapeLayer *ring = circleLayer(c, kOrbit, [UIColor clearColor], [MeshTheme accentDim]);
        ring.lineWidth = 1;
        [_stage.layer addSublayer:ring];
        CABasicAnimation *scale = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
        scale.fromValue = @0.2; scale.toValue = @1.15;
        CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
        fade.fromValue = @0.8; fade.toValue = @0;
        CAAnimationGroup *g = [CAAnimationGroup animation];
        g.animations = @[scale, fade]; g.duration = 2.4; g.repeatCount = HUGE_VALF;
        g.beginTime = CACurrentMediaTime() + i * 0.8;
        ring.opacity = 0;
        [ring addAnimation:g forKey:@"pulse"];
    }

    for (NSUInteger i = 0; i < n; i++) {
        CGFloat a = -M_PI_2 + i * 2 * M_PI / n;
        CGPoint p = CGPointMake(c.x + kOrbit * cos(a), c.y + kOrbit * sin(a));
        // Linie vom Rand des Schilds bis zum Rand des Knotens, nicht durch beide hindurch.
        CGFloat from = kCore / 2 + kCoreGap, to = kOrbit - kNode / 2;
        CAShapeLayer *link = [CAShapeLayer layer];
        UIBezierPath *path = [UIBezierPath bezierPath];
        [path moveToPoint:CGPointMake(c.x + from * cos(a), c.y + from * sin(a))];
        [path addLineToPoint:CGPointMake(c.x + to * cos(a), c.y + to * sin(a))];
        link.path = path.CGPath;
        link.strokeColor = [MeshTheme line].CGColor;
        link.lineWidth = 1.5f;
        link.lineDashPattern = @[@4, @4];
        [_stage.layer addSublayer:link];
        [_links addObject:link];

        CAShapeLayer *node = circleLayer(p, kNode / 2, [MeshTheme surfaceHi], [MeshTheme line]);
        CABasicAnimation *blink = [CABasicAnimation animationWithKeyPath:@"opacity"];
        blink.fromValue = @1; blink.toValue = @0.35; blink.duration = 0.7;
        blink.autoreverses = YES; blink.repeatCount = HUGE_VALF; blink.beginTime = CACurrentMediaTime() + i * 0.2;
        [node addAnimation:blink forKey:@"wait"];
        [_stage.layer addSublayer:node];
        [_nodes addObject:node];
    }

    UIImageView *core = [[UIImageView alloc] initWithFrame:CGRectMake(c.x - kCore / 2, c.y - kCore / 2, kCore, kCore)];
    core.image = [MeshGlyphs icon:@"shield" color:[MeshTheme accent] size:kCore];
    [_stage addSubview:core];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(update)
                                                 name:MeshConnectionChangedNotification object:nil];
    _progress = -1;
    [self update];
    _tick = [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(tickPercent) userInfo:nil repeats:YES];
}

- (void)update {
    MeshSession *s = [MeshSession shared];
    NSUInteger up = s.connectedRelayCount, total = s.relayCount;
    for (NSUInteger i = 0; i < _nodes.count; i++) {
        BOOL on = i < up;   // Reihenfolge egal: gezeigt wird die Anzahl
        CAShapeLayer *node = _nodes[i], *link = _links[i];
        if (on && [node animationForKey:@"wait"]) {
            [node removeAnimationForKey:@"wait"];
            node.fillColor = [MeshTheme accent].CGColor; node.strokeColor = [MeshTheme accent].CGColor;
            link.strokeColor = [MeshTheme accent].CGColor; link.lineDashPattern = nil;
        }
    }
    [self showStatus];
    _count.text = LF(@"%d of %d relays", (int)up, (int)total);
    if (self.inspect) return;   // aus der Leiste: bleibt offen, bis man tippt
    // Weiter: verbunden (kurz zeigen), Tor gescheitert (Meldung lesen lassen) oder kTimeout ohne Fortschritt.
    int progress = (int)up * 1000 + (s.torReady ? 100 : s.torBootstrapPercent);
    NSTimeInterval delay = up ? kShowConnected : s.torFailed ? kShowFailed : kTimeout;
    if (up || s.torFailed || progress != _progress) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(finish) object:nil];
        [self performSelector:@selector(finish) withObject:nil afterDelay:delay];
    }
    _progress = progress;
}

// Statuszeile; mit Tor die weich mitlaufenden Prozente und die Zwiebel dahinter.
- (void)showStatus {
    MeshSession *s = [MeshSession shared];
    BOOL up = s.connectedRelayCount > 0;
    if (up) _status.text = s.usesTor ? L(@"Connected via Tor") : L(@"Connected to the network");
    else if (!s.usesTor) _status.text = L(@"Connecting to the network …");
    else if (s.torFailed) _status.text = L(@"Tor is not running — Mesh stays offline");
    else if (s.torReady) _status.text = L(@"Connecting via Tor …");
    else _status.text = LF(@"Starting Tor … %d%%", (int)_shown);
    _first.hidden = !(s.usesTor && !up && !s.torReady && !s.torFailed && _firstStart);
    [self placeOnion:s.usesTor];
}

// Zwiebel hinter dem Text, beides mittig. Die Breite richtet sich nach "… 100 %", damit der Text
// nicht wackelt, während die Zahl läuft.
- (void)placeOnion:(BOOL)tor {
    CGFloat W = self.view.bounds.size.width;
    _onion.hidden = !tor;
    _status.textAlignment = tor ? NSTextAlignmentLeft : NSTextAlignmentCenter;
    if (!tor) { _status.frame = CGRectMake(20, _status.frame.origin.y, W - 40, _status.frame.size.height); return; }
    NSString *widest = [_status.text hasSuffix:@"%"] ? LF(@"Starting Tor … %d%%", 100) : _status.text;
    CGFloat tw = MIN([widest sizeWithFont:_status.font].width, W - 70), x = roundf((W - tw - 24) / 2);
    _status.frame = CGRectMake(x, _status.frame.origin.y, tw + 2, _status.frame.size.height);
    _onion.frame = CGRectMake(x + tw + 6, _status.frame.origin.y + 2, 18, 18);
}

// Ziel der Anzeige: echter Stand; danach darf sie bis kurz vor den nächsten echten Schritt kriechen
// (Tor meldet nur Sprünge, zwischen denen am iPod Minuten liegen können), nie darüber hinaus.
static int nextTorStep(int p) {
    static const int steps[] = { 5, 10, 14, 15, 20, 25, 30, 40, 45, 50, 55, 61, 68, 75, 80, 85, 90, 95, 100 };
    for (size_t i = 0; i < sizeof(steps) / sizeof(steps[0]); i++) if (steps[i] > p) return steps[i];
    return 100;
}

- (void)tickPercent {
    MeshSession *s = [MeshSession shared];
    float target = (s.connectedRelayCount || s.torReady) ? 100 : s.torBootstrapPercent;
    float ceiling = target >= 100 ? 100 : nextTorStep((int)target) - 0.5f;
    if (_shown < target) _shown += MAX(0.4f, (target - _shown) * 0.15f);       // aufholen, weich
    else if (_shown < ceiling) _shown += (ceiling - _shown) * 0.004f + 0.01f;  // kriechen, immer langsamer
    _shown = MIN(_shown, target >= 100 ? 100 : ceiling);
    [self showStatus];
}

- (void)finish {
    if (_finished) return;
    if (self.inspect) { [self cancel]; [self mesh_dismissAnimated:YES]; return; }
    [self cancel];
    // Wurde inzwischen gesperrt (App im Hintergrund), nicht zur Chatliste wechseln.
    if ([MeshSession shared].unlocked && self.onDone) self.onDone();
}

- (void)cancel {
    _finished = YES;
    [_tick invalidate]; _tick = nil;
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self cancel];
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
