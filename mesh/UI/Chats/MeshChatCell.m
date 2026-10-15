#import "MeshChatCell.h"
#import "MeshEmojiLabel.h"
#import "MeshAvatarView.h"
#import "MeshTheme.h"

@implementation MeshChatCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
    if ((self = [super initWithStyle:style reuseIdentifier:rid])) {
        self.backgroundColor = [MeshTheme bg];
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        UIView *hl = [[UIView alloc] init]; hl.backgroundColor = [MeshTheme surface]; self.selectedBackgroundView = hl;
        _avatar = [[MeshAvatarView alloc] initWithFrame:CGRectZero source:MeshAvatarContact];
        [self.contentView addSubview:_avatar];
        _nameLabel = [[MeshEmojiLabel alloc] init]; _nameLabel.font = [MeshTheme nameFont]; _nameLabel.textColor = [MeshTheme ink];
        _nameLabel.backgroundColor = [UIColor clearColor]; [self.contentView addSubview:_nameLabel];
        _previewLabel = [[MeshEmojiLabel alloc] init]; _previewLabel.font = [MeshTheme previewFont]; _previewLabel.textColor = [MeshTheme muted];
        _previewLabel.backgroundColor = [UIColor clearColor]; [self.contentView addSubview:_previewLabel];
        _timeLabel = [[UILabel alloc] init]; _timeLabel.font = [MeshTheme timeFont]; _timeLabel.textColor = [MeshTheme faint];
        _timeLabel.backgroundColor = [UIColor clearColor]; _timeLabel.textAlignment = NSTextAlignmentRight;
        [self.contentView addSubview:_timeLabel];
        _sep = [[UIView alloc] init]; _sep.backgroundColor = [MeshTheme line]; [self.contentView addSubview:_sep];
        _identityBadge = [[MeshAvatarView alloc] initWithFrame:CGRectZero source:MeshAvatarIdenticon];
        _identityBadge.layer.borderWidth = 2;
        _identityBadge.layer.borderColor = [MeshTheme bg].CGColor;
        _identityBadge.hidden = YES;
        [self.contentView addSubview:_identityBadge];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.contentView.bounds.size.width, right = 14, timeW = 56;
    _avatar.frame       = CGRectMake(14, 9, 52, 52);
    _identityBadge.frame = CGRectMake(14 + 52 - 20, 9 + 52 - 20, 24, 24);
    _timeLabel.frame    = CGRectMake(w - right - timeW, 16, timeW, 14);
    _nameLabel.frame    = CGRectMake(78, 14, w - 78 - right - timeW - 6, 20);
    _previewLabel.frame = CGRectMake(78, 36, w - 78 - right - 6, 18);
    _sep.frame          = CGRectMake(78, self.contentView.bounds.size.height - 0.5f, w - 78, 0.5f);
}
@end
