// Leiste der Hauptseiten: Logo, Titel, Untertitel und Verbindungs-Chip.
// Der Chip folgt MeshConnectionChangedNotification von selbst.
#import <UIKit/UIKit.h>

@interface MeshTopBar : UIView
+ (CGFloat)height;   // inklusive MeshTheme topInset
- (instancetype)initWithWidth:(CGFloat)width title:(NSString *)title subtitle:(NSString *)subtitle;
@end
