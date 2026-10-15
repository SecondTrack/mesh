#import "MeshBanner.h"
#import "MeshEmojiLabel.h"
#import "MeshTheme.h"
#import "MeshNotifications.h"

static UIView *gBanner;
static const CGFloat kHeight = 56, kMargin = 8;
static const NSTimeInterval kShown = 3;

@implementation MeshBanner

+ (void)hide {
    UIView *b = gBanner;
    gBanner = nil;
    [UIView animateWithDuration:0.2 animations:^{ b.alpha = 0; } completion:^(BOOL f) { [b removeFromSuperview]; }];
}

+ (void)showTitle:(NSString *)title text:(NSString *)text {
    UIWindow *win = [UIApplication sharedApplication].keyWindow;
    if (!win) return;
    [gBanner removeFromSuperview];
    static dispatch_once_t once;
    dispatch_once(&once, ^{   // beim Sperren nichts Lesbares stehen lassen
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(hide) name:MeshWillLockNotification object:nil];
    });
    CGFloat W = win.bounds.size.width;
    UIView *b = [[UIView alloc] initWithFrame:CGRectMake(kMargin, -kHeight, W - 2 * kMargin, kHeight)];
    b.backgroundColor = [MeshTheme surfaceHi];
    b.layer.cornerRadius = 14;
    b.layer.borderWidth = 0.5f;
    b.layer.borderColor = [MeshTheme line].CGColor;
    UILabel *t = [[MeshEmojiLabel alloc] initWithFrame:CGRectMake(14, 8, b.bounds.size.width - 28, 20)];
    t.font = [MeshTheme labelFont]; t.textColor = [MeshTheme accent]; t.backgroundColor = [UIColor clearColor];
    t.text = title;
    [b addSubview:t];
    UILabel *m = [[MeshEmojiLabel alloc] initWithFrame:CGRectMake(14, 28, b.bounds.size.width - 28, 20)];
    m.font = [MeshTheme previewFont]; m.textColor = [MeshTheme ink]; m.backgroundColor = [UIColor clearColor];
    m.text = text;
    [b addSubview:m];
    [b addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hide)]];
    [win addSubview:b];
    gBanner = b;
    [UIView animateWithDuration:0.25 animations:^{ b.frame = CGRectOffset(b.frame, 0, kHeight + kMargin + 4); }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kShown * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (gBanner == b) [self hide];
    });
}

@end
