// QR-Code als UIImage aus einem String (via gevendortem qrcodegen).
#import <UIKit/UIKit.h>

@interface MeshQR : NSObject
// Rendert `s` als QR (sizePx × sizePx). fg = Module, bg = Hintergrund. nil bei Fehler.
+ (UIImage *)imageForString:(NSString *)s sizePx:(CGFloat)px module:(UIColor *)fg background:(UIColor *)bg;
@end
