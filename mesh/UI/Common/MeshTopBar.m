#import "MeshTopBar.h"
#import "MeshTheme.h"
#import "MeshGlyphs.h"
#import "MeshSession.h"
#import "MeshL10n.h"
#import "MeshCompat.h"
#import "ConnectViewController.h"

static const CGFloat kBarHeight = 66, kChipHeight = 28;

@implementation MeshTopBar {
    UIView *_chip;
    UIImageView *_chipIcon;
    UILabel *_chipLabel;
}

+ (CGFloat)height { return [MeshTheme topInset] + kBarHeight; }

- (instancetype)initWithWidth:(CGFloat)width title:(NSString *)title subtitle:(NSString *)subtitle {
    if ((self = [super initWithFrame:CGRectMake(0, 0, width, [MeshTopBar height])])) {
        CGFloat top = [MeshTheme topInset];
        UIImageView *logo = [[UIImageView alloc] initWithFrame:CGRectMake(14, top + 14, 38, 38)];
        logo.image = [MeshGlyphs logo:38];
        [self addSubview:logo];
        [self addLabel:title font:[MeshTheme brandFont] color:[MeshTheme ink] frame:CGRectMake(62, top + 12, width - 180, 30)];
        [self addLabel:subtitle font:[MeshTheme timeFont] color:[MeshTheme muted] frame:CGRectMake(62, top + 43, width - 180, 14)];

        _chip = [[UIView alloc] init];
        _chip.layer.cornerRadius = kChipHeight / 2;
        _chip.layer.borderWidth = 1;
        _chip.layer.borderColor = [MeshTheme line].CGColor;
        _chipIcon = [[UIImageView alloc] initWithFrame:CGRectMake(11, (kChipHeight - 15) / 2, 15, 15)];
        [_chip addSubview:_chipIcon];
        _chipLabel = [[UILabel alloc] init];
        _chipLabel.font = [MeshTheme timeFont];
        _chipLabel.backgroundColor = [UIColor clearColor];
        [_chip addSubview:_chipLabel];
        [_chip addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(showConnection)]];
        [self addSubview:_chip];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateConnection)
                                                     name:MeshConnectionChangedNotification object:nil];
        [self updateConnection];
    }
    return self;
}

- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; }

- (void)addLabel:(NSString *)text font:(UIFont *)font color:(UIColor *)color frame:(CGRect)frame {
    UILabel *l = [[UILabel alloc] initWithFrame:frame];
    l.text = text; l.font = font; l.textColor = color; l.backgroundColor = [UIColor clearColor];
    [self addSubview:l];
}

// Chip passt sich der Textbreite an und steht rechtsbündig.
- (void)updateConnection {
    MeshSession *session = [MeshSession shared];
    BOOL online = session.anyRelayConnected;
    NSString *text = online ? L(@"Connected") : session.networkReachable ? L(@"Connecting …") : L(@"Offline");
    UIColor *color = online ? [MeshTheme accent] : [MeshTheme faint];
    _chipLabel.text = text;
    _chipLabel.textColor = color;
    _chipIcon.image = [MeshGlyphs icon:@"shield" color:color size:15];
    _chip.backgroundColor = online ? [MeshTheme accentDeep] : [MeshTheme surface];
    CGFloat lw = [text sizeWithFont:[MeshTheme timeFont]].width, chipW = 32 + lw + 12;
    _chip.frame = CGRectMake(self.bounds.size.width - 14 - chipW, [MeshTheme topInset] + 20, chipW, kChipHeight);
    _chipLabel.frame = CGRectMake(32, 0, lw + 4, kChipHeight);
}

// Chip antippen: die Verbindungs-Animation vom Start, mit dem aktuellen Stand (verbunden: alle
// Knoten leuchten; sonst der Fortschritt). Antippen schließt sie.
- (void)showConnection {
    UIResponder *r = self;
    while (r && ![r isKindOfClass:[UIViewController class]]) r = r.nextResponder;
    UIViewController *host = (UIViewController *)r;
    if (host.navigationController) host = host.navigationController;
    ConnectViewController *connect = [[ConnectViewController alloc] init];
    connect.inspect = YES;
    [host mesh_present:connect animated:YES];
}

@end
