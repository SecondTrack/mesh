#import "VoiceEffectViewController.h"
#import "MeshScreen.h"
#import "MeshTheme.h"
#import "MeshPageHeader.h"
#import "MeshControls.h"
#import "MeshGlyphs.h"
#import "MeshL10n.h"
#import "MeshVoiceSettings.h"

static const CGFloat kRow = 64, kTile = 34, kPad = 16;

@implementation VoiceEffectViewController {
    UIScrollView *_scroll;
    NSMutableArray *_tiles, *_checks;   // je Effekt: Symbol-Kachel (UIImageView) und Haken
}

- (void)loadView {
    [self mesh_loadScreen];
    CGFloat W = self.view.bounds.size.width;
    _scroll = [self mesh_addPageTitled:L(@"Voice changer")];
    _tiles = [NSMutableArray array]; _checks = [NSMutableArray array];

    CGFloat y = 14;
    [_scroll addSubview:[MeshControls sectionLabelWithFrame:CGRectMake(kPad, y, W - 2 * kPad, 18) text:[L(@"Effect for voice messages") uppercaseString]]];
    y += 26;

    NSArray *effects = [MeshVoiceSettings allEffects];
    for (NSUInteger i = 0; i < effects.count; i++) {
        UIControl *row = [[UIControl alloc] initWithFrame:CGRectMake(0, y, W, kRow)];
        row.tag = (NSInteger)i;
        [row addTarget:self action:@selector(tapRow:) forControlEvents:UIControlEventTouchUpInside];

        UIView *tile = [[UIView alloc] initWithFrame:CGRectMake(kPad, (kRow - kTile) / 2, kTile, kTile)];
        tile.backgroundColor = [MeshTheme surfaceHi];
        tile.layer.cornerRadius = 10;
        tile.userInteractionEnabled = NO;
        UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectMake((kTile - 20) / 2, (kTile - 20) / 2, 20, 20)];
        [tile addSubview:icon];
        [row addSubview:tile];
        [_tiles addObject:icon];

        UILabel *label = [MeshControls labelWithFrame:CGRectMake(kPad + kTile + 14, 0, W - (kPad + kTile + 14) - 50, kRow) font:[MeshTheme bodyFont] color:[MeshTheme ink]];
        label.text = [MeshVoiceSettings effectLabel:effects[i]];
        [row addSubview:label];

        UIImageView *check = [[UIImageView alloc] initWithFrame:CGRectMake(W - kPad - 22, (kRow - 22) / 2, 22, 22)];
        check.image = [MeshGlyphs icon:@"check" color:[MeshTheme accent] size:22];
        [row addSubview:check];
        [_checks addObject:check];

        UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(kPad + kTile + 14, kRow - 0.5f, W - (kPad + kTile + 14), 0.5f)];
        sep.backgroundColor = [MeshTheme line];
        [row addSubview:sep];
        [_scroll addSubview:row];
        y += kRow;
    }

    // Hinweis wie in der Android-App (orangefarbener Grund)
    y += 16;
    UILabel *hint = [MeshControls labelWithFrame:CGRectZero font:[MeshTheme previewFont] color:[MeshTheme ink]];
    hint.numberOfLines = 0;
    hint.text = L(@"The effect is baked in during recording and sent encrypted. “Anonymous” shifts pitch and timbre separately (no speed change) and varies per message, making speaker recognition harder. No changer makes a voice guaranteed unrecognizable: speaking style and content remain.");
    CGFloat tw = W - 2 * kPad - 24;
    CGSize ts = [hint.text sizeWithFont:hint.font constrainedToSize:CGSizeMake(tw, 1000) lineBreakMode:NSLineBreakByWordWrapping];
    UIView *box = [[UIView alloc] initWithFrame:CGRectMake(kPad, y, W - 2 * kPad, ceilf(ts.height) + 24)];
    box.backgroundColor = [UIColor colorWithRed:1.0f green:0x7A / 255.0f blue:0x33 / 255.0f alpha:0x22 / 255.0f];
    box.layer.cornerRadius = 12;
    hint.frame = CGRectMake(12, 12, tw, ceilf(ts.height));
    [box addSubview:hint];
    [_scroll addSubview:box];
    y += box.frame.size.height + 30;
    _scroll.contentSize = CGSizeMake(W, y);
    [self refresh];
}

- (void)refresh {
    NSString *current = [MeshVoiceSettings currentEffect];
    NSArray *effects = [MeshVoiceSettings allEffects];
    for (NSUInteger i = 0; i < effects.count; i++) {
        BOOL on = [effects[i] isEqualToString:current];
        ((UIImageView *)_tiles[i]).image = [MeshGlyphs icon:@"wave" color:(on ? [MeshTheme accent] : [MeshTheme faint]) size:20];
        ((UIView *)_checks[i]).hidden = !on;
    }
}

- (void)tapRow:(UIControl *)row {
    NSArray *effects = [MeshVoiceSettings allEffects];
    if (row.tag < 0 || row.tag >= (NSInteger)effects.count) return;
    [MeshVoiceSettings setCurrentEffect:effects[(NSUInteger)row.tag]];
    [self refresh];
}

@end
