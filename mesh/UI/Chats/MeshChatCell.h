// Zeile der Chatliste: 52er-Avatar, Name, Vorschau, Uhrzeit, Trennlinie ab 78. Im gemeinsamen
// Posteingang zeigt eine kleine Plakette am Avatar, zu welcher eigenen Identität der Chat gehört.
#import <UIKit/UIKit.h>

@class MeshAvatarView;

@interface MeshChatCell : UITableViewCell
@property (nonatomic, strong) MeshAvatarView *avatar;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *previewLabel;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UIView  *sep;
@property (nonatomic, strong) MeshAvatarView *identityBadge;   // versteckt außer im gemeinsamen Posteingang
@end
