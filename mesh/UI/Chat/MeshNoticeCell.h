// Hinweiszeile im Chatverlauf (z.B. "Selbstlöschen auf 1 Tag gestellt"): mittig, ohne Blase.
#import <UIKit/UIKit.h>

@interface MeshNoticeCell : UITableViewCell
- (void)setNotice:(NSString *)text width:(CGFloat)width;
+ (CGFloat)heightForNotice:(NSString *)text width:(CGFloat)width;
@end
