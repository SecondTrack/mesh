// Symbole (24er-Raster, Strichstärke 1,9, runde Enden) und das Mesh-Logo,
// als Vektorpfade gezeichnet und als UIImage geliefert. Gleiche Pfade wie in der Android-App.
#import <UIKit/UIKit.h>

@interface MeshGlyphs : NSObject
// Linien-Symbol nach Name: chat, key, scan, send, back, forward, add, shield, camera, check,
// doublecheck, search, mic; Tastatur: shift, capslock, backspace, globe, smiley. Farbe und Kantenlänge in Punkten.
+ (UIImage *)icon:(NSString *)name color:(UIColor *)color size:(CGFloat)size;
// Mesh-Logo (Mint-Knoten), quadratisch.
+ (UIImage *)logo:(CGFloat)size;
// Gefüllte Symbole für die Sprachnachrichten: Stopp (abgerundetes Quadrat), Play/Pause.
+ (UIImage *)stopIcon:(CGFloat)size color:(UIColor *)color;
+ (UIImage *)playPauseIcon:(BOOL)playing size:(CGFloat)size color:(UIColor *)color;
@end
