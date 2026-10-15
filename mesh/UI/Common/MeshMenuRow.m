#import "MeshMenuRow.h"
#import "MeshEmojiLabel.h"
#import "MeshTheme.h"
#import "MeshGlyphs.h"

static const CGFloat kRowHeight = 64, kTextX = 68;

@implementation MeshMenuRow {
    UIImageView *_chevron;
    UILabel *_detailLabel;
}

+ (CGFloat)height { return kRowHeight; }

+ (CGFloat)addTo:(UIView *)host y:(CGFloat)y width:(CGFloat)width icon:(NSString *)icon title:(NSString *)title
        subtitle:(NSString *)subtitle target:(id)target action:(SEL)action {
    MeshMenuRow *row = [self rowAtY:y width:width icon:icon title:title subtitle:subtitle];
    [row addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    [host addSubview:row];
    return y + [self height];
}

+ (instancetype)rowAtY:(CGFloat)y width:(CGFloat)w icon:(NSString *)icon title:(NSString *)title subtitle:(NSString *)subtitle {
    MeshMenuRow *row = [self buttonWithType:UIButtonTypeCustom];
    row.frame = CGRectMake(0, y, w, kRowHeight);

    UIView *tile = [[UIView alloc] initWithFrame:CGRectMake(16, 13, 38, 38)];
    tile.backgroundColor = [MeshTheme surfaceHi];
    tile.layer.cornerRadius = [MeshTheme tileRadius];
    tile.userInteractionEnabled = NO;
    UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(9, 9, 20, 20)];
    iv.image = [MeshGlyphs icon:icon color:[MeshTheme accent] size:20];
    [tile addSubview:iv];
    [row addSubview:tile];

    UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(kTextX, 13, w - kTextX - 40, 20)];
    t.text = title; t.font = [MeshTheme bodyFont]; t.textColor = [MeshTheme ink]; t.backgroundColor = [UIColor clearColor];
    [row addSubview:t];
    UILabel *s = [[MeshEmojiLabel alloc] initWithFrame:CGRectMake(kTextX, 33, w - kTextX - 40, 16)];
    s.text = subtitle; s.font = [MeshTheme timeFont]; s.textColor = [MeshTheme muted]; s.backgroundColor = [UIColor clearColor];
    [row addSubview:s];

    row->_chevron = [[UIImageView alloc] initWithFrame:CGRectMake(w - 30, (kRowHeight - 20) / 2, 20, 20)];
    row->_chevron.image = [MeshGlyphs icon:@"forward" color:[MeshTheme faint] size:20];
    [row addSubview:row->_chevron];
    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(kTextX, kRowHeight - 0.5f, w - kTextX, 0.5f)];
    line.backgroundColor = [MeshTheme line];
    [row addSubview:line];
    return row;
}

- (void)setDetail:(NSString *)detail {
    _detail = [detail copy];
    if (!_detailLabel) {
        _detailLabel = [[UILabel alloc] initWithFrame:CGRectMake(self.bounds.size.width - 110, 0, 100, kRowHeight)];
        _detailLabel.font = [MeshTheme labelFont];
        _detailLabel.textColor = [MeshTheme accent];
        _detailLabel.textAlignment = NSTextAlignmentRight;
        _detailLabel.backgroundColor = [UIColor clearColor];
        [self addSubview:_detailLabel];
    }
    _detailLabel.text = _detail;
    _chevron.hidden = _detail.length > 0;
}

@end
