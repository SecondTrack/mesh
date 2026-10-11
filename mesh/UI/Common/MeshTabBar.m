#import "MeshTabBar.h"
#import "MeshTheme.h"
#import "MeshGlyphs.h"
#import "MeshAvatarView.h"
#import "MeshSession.h"
#import "MeshL10n.h"

static const CGFloat kBarHeight = 66, kPillHeight = 46, kGap = 12;

@implementation MeshTabBar {
    MeshTab _selected;
}

+ (CGFloat)height { return kBarHeight; }

- (instancetype)initWithFrame:(CGRect)frame selected:(MeshTab)selected {
    if ((self = [super initWithFrame:frame])) {
        _selected = selected;
        self.backgroundColor = [MeshTheme surface];
        UIView *line = [[UIView alloc] initWithFrame:CGRectMake(0, 0, frame.size.width, 0.5f)];
        line.backgroundColor = [MeshTheme line];
        [self addSubview:line];

        CGFloat pw = (frame.size.width - 3 * kGap) / 2, py = (kBarHeight - kPillHeight) / 2;
        UIImageView *chatIcon = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 23, 23)];
        chatIcon.image = [MeshGlyphs icon:@"chat" color:(selected == MeshTabChats ? [MeshTheme accent] : [MeshTheme muted]) size:23];
        [self addPill:CGRectMake(kGap, py, pw, kPillHeight) icon:chatIcon label:L(@"Chats") tab:MeshTabChats];

        MeshAvatarView *me = [[MeshAvatarView alloc] initWithFrame:CGRectMake(0, 0, 26, 26) source:MeshAvatarSelf];
        me.pubkey = [[MeshSession shared] myPubkeyHex];
        [self addPill:CGRectMake(2 * kGap + pw, py, pw, kPillHeight) icon:me label:L(@"Me") tab:MeshTabMe];
    }
    return self;
}

// Pille: Symbol und Text mittig; die gewählte ist hervorgehoben und nicht antippbar.
- (void)addPill:(CGRect)f icon:(UIView *)icon label:(NSString *)label tab:(MeshTab)tab {
    BOOL on = tab == _selected;
    UIButton *pill = [UIButton buttonWithType:UIButtonTypeCustom];
    pill.frame = f;
    pill.tag = tab;
    pill.backgroundColor = on ? [[MeshTheme accent] colorWithAlphaComponent:0.16f] : [MeshTheme surfaceHi];
    pill.layer.cornerRadius = f.size.height / 2;
    if (!on) [pill addTarget:self action:@selector(tapPill:) forControlEvents:UIControlEventTouchUpInside];

    UIFont *font = [MeshTheme nameFont];
    CGFloat lw = [label sizeWithFont:font].width, iw = icon.frame.size.width;
    CGFloat x = (f.size.width - (iw + 9 + lw)) / 2;
    icon.frame = CGRectMake(x, (f.size.height - icon.frame.size.height) / 2, iw, icon.frame.size.height);
    icon.userInteractionEnabled = NO;
    [pill addSubview:icon];
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(x + iw + 9, 0, lw + 4, f.size.height)];
    l.text = label; l.font = font; l.backgroundColor = [UIColor clearColor];
    l.textColor = on ? [MeshTheme accent] : [MeshTheme muted];
    [pill addSubview:l];
    [self addSubview:pill];
}

- (void)tapPill:(UIButton *)pill { if (self.onSelect) self.onSelect((MeshTab)pill.tag); }

@end
