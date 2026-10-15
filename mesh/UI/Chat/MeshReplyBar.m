#import "MeshReplyBar.h"
#import "MeshEmojiLabel.h"
#import "MeshTheme.h"
#import "MeshGlyphs.h"

static const CGFloat kHeight = 46, kBar = 3, kClose = 44;

@implementation MeshReplyBar {
    UILabel *_author, *_text;
}

+ (CGFloat)height { return kHeight; }

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        CGFloat W = frame.size.width;
        self.backgroundColor = [MeshTheme surface];
        UIView *line = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, 0.5f)];
        line.backgroundColor = [MeshTheme line];
        [self addSubview:line];
        UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(12, 7, kBar, kHeight - 14)];
        bar.backgroundColor = [MeshTheme accent];
        [self addSubview:bar];
        _author = [self labelAt:CGRectMake(22, 6, W - 22 - kClose, 17) color:[MeshTheme accent]];
        _text = [self labelAt:CGRectMake(22, 23, W - 22 - kClose, 17) color:[MeshTheme muted]];
        _closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _closeButton.frame = CGRectMake(W - kClose, 1, kClose, kHeight - 2);
        [_closeButton setImage:[MeshGlyphs icon:@"close" color:[MeshTheme muted] size:18] forState:UIControlStateNormal];
        [self addSubview:_closeButton];
    }
    return self;
}

- (UILabel *)labelAt:(CGRect)frame color:(UIColor *)color {
    UILabel *l = [[MeshEmojiLabel alloc] initWithFrame:frame];
    l.font = [MeshTheme timeFont];
    l.textColor = color;
    l.backgroundColor = [UIColor clearColor];
    [self addSubview:l];
    return l;
}

- (void)setAuthor:(NSString *)author text:(NSString *)text {
    _author.text = author;
    _text.text = text;
}

@end
