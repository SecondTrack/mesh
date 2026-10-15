#import "MeshPageHeader.h"
#import "MeshEmojiLabel.h"
#import "MeshTheme.h"
#import "MeshGlyphs.h"

static const CGFloat kBarHeight = 52;   // wie die Kopfzeile im Chat

@implementation MeshPageHeader

+ (CGFloat)height { return [MeshTheme topInset] + kBarHeight; }

- (instancetype)initWithWidth:(CGFloat)width height:(CGFloat)height target:(id)target back:(SEL)back {
    if ((self = [super initWithFrame:CGRectMake(0, 0, width, height)])) {
        self.backgroundColor = [MeshTheme surface];
        UIView *line = [[UIView alloc] initWithFrame:CGRectMake(0, height - 0.5f, width, 0.5f)];
        line.backgroundColor = [MeshTheme line];
        [self addSubview:line];
        CGFloat top = [MeshTheme topInset], barH = height - top;
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.frame = CGRectMake(6, top + (barH - 34) / 2, 40, 34);
        [b setImage:[MeshGlyphs icon:@"back" color:[MeshTheme accent] size:22] forState:UIControlStateNormal];
        [b addTarget:target action:back forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:b];
        _titleLabel = [[MeshEmojiLabel alloc] initWithFrame:CGRectMake(50, top, width - 100, barH)];
        _titleLabel.font = [MeshTheme titleFont];
        _titleLabel.textColor = [MeshTheme ink];
        _titleLabel.backgroundColor = [UIColor clearColor];
        [self addSubview:_titleLabel];
    }
    return self;
}

- (instancetype)initWithWidth:(CGFloat)width title:(NSString *)title target:(id)target back:(SEL)back {
    if ((self = [self initWithWidth:width height:[MeshPageHeader height] target:target back:back]))
        _titleLabel.text = title;
    return self;
}

@end

@implementation UIViewController (MeshBack)
- (void)mesh_goBack {
    [self.view endEditing:YES];
    [self.navigationController popViewControllerAnimated:YES];
}

- (UIScrollView *)mesh_addPageTitled:(NSString *)title {
    CGFloat W = self.view.bounds.size.width, top = [MeshPageHeader height];
    [self.view addSubview:[[MeshPageHeader alloc] initWithWidth:W title:title target:self back:@selector(mesh_goBack)]];
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, top, W, self.view.bounds.size.height - top)];
    [self.view addSubview:scroll];
    return scroll;
}

@end
