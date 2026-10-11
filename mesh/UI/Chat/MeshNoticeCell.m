#import "MeshNoticeCell.h"
#import "MeshTheme.h"
#import "MeshEmoji.h"

static const CGFloat kPadX = 14, kPadY = 5, kRowPad = 6, kMaxFrac = 0.8f;

@implementation MeshNoticeCell {
    UILabel *_label;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    if ((self = [super initWithStyle:style reuseIdentifier:rid])) {
        self.backgroundColor = [MeshTheme bg];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _label = [[UILabel alloc] init];
        _label.font = [MeshTheme timeFont];
        _label.textColor = [MeshTheme muted];
        _label.backgroundColor = [MeshTheme surface];
        _label.textAlignment = NSTextAlignmentCenter;
        _label.numberOfLines = 0;
        _label.layer.cornerRadius = 10;
        _label.clipsToBounds = YES;
        [self.contentView addSubview:_label];
    }
    return self;
}

+ (CGSize)textSize:(NSString *)text width:(CGFloat)width {
    return [MeshEmoji textSize:text font:[MeshTheme timeFont] constrainedTo:CGSizeMake(width * kMaxFrac - 2 * kPadX, 200)];
}

- (void)setNotice:(NSString *)text width:(CGFloat)W {
    CGSize s = [MeshNoticeCell textSize:text width:W];
    CGFloat w = s.width + 2 * kPadX, h = s.height + 2 * kPadY;
    _label.text = text;
    _label.frame = CGRectMake(roundf((W - w) / 2), kRowPad, w, h);
}

+ (CGFloat)heightForNotice:(NSString *)text width:(CGFloat)width {
    return [self textSize:text width:width].height + 2 * kPadY + 2 * kRowPad;
}

@end
