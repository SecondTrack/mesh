// Kurzer Hinweis oben im Bild, z.B. bei einer Nachricht in einem anderen Chat. Verschwindet von
// selbst; ein neuer ersetzt den alten.
#import <UIKit/UIKit.h>

@interface MeshBanner : NSObject
+ (void)showTitle:(NSString *)title text:(NSString *)text;
@end
