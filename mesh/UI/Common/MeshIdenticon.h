// Avatar aus dem Pubkey: 5×5-Muster, spiegelsymmetrisch, in Mint-Tönen.
// Gleicher Schlüssel ergibt immer dasselbe Bild, so erkennt man Kontakte auch ohne Profilbild.
#import <UIKit/UIKit.h>

@interface MeshIdenticon : NSObject
// Zeichnet in rect (als Kreis geclippt) einen Identicon aus seed (hex-Pubkey).
+ (void)drawSeed:(NSString *)seed inRect:(CGRect)rect context:(CGContextRef)ctx;
@end
