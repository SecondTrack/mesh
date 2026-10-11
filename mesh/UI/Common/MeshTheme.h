// Farben, Schriften und Maße des Mesh-Looks (gleiche Werte wie in der Android-App).
// Dunkel und ruhig; Mint steht für sicher/verbunden.
#import <UIKit/UIKit.h>

// Hex -> UIColor (0xRRGGBB), Alpha 1.
#define MESH_RGB(hex) [UIColor colorWithRed:((float)((hex>>16)&0xFF))/255.0f \
                                      green:((float)((hex>>8)&0xFF))/255.0f \
                                       blue:((float)(hex&0xFF))/255.0f alpha:1.0f]

@interface MeshTheme : NSObject

// Farben
+ (UIColor *)bg;          // 0A0F0E  Grund: fast schwarz, kühl
+ (UIColor *)surface;     // 111A17  Karten / Leisten
+ (UIColor *)surfaceHi;   // 18231F  erhöhte Fläche / them-Blase
+ (UIColor *)field;       // 16211D  Eingabefelder
+ (UIColor *)line;        // 213029  Trennlinien / Rahmen
+ (UIColor *)accent;      // 2FE6A8  Signal-Mint = sicher/verbunden
+ (UIColor *)accentDim;   // 1C8F6B
+ (UIColor *)accentDeep;  // 0F3A2E  me-Blase
+ (UIColor *)ink;         // E8F0ED
+ (UIColor *)muted;       // 8A9A94
+ (UIColor *)faint;       // 5A6B65
+ (UIColor *)bubbleMeInk; // E6FBF2
+ (UIColor *)danger;      // FF6B6B

// Schrift: UI = HelveticaNeue, Schlüssel = Mono
+ (UIFont *)titleFont;    // 20 Bold
+ (UIFont *)nameFont;     // 16 SemiBold
+ (UIFont *)bodyFont;     // 15 Regular
+ (UIFont *)previewFont;  // 14 Regular (muted)
+ (UIFont *)labelFont;    // 11 SemiBold (accentDim, +letterspacing)
+ (UIFont *)timeFont;     // 11 Regular (faint)
+ (UIFont *)monoFont;     // 12 Mono
+ (UIFont *)monoBigFont;  // 14 Mono Medium
+ (UIFont *)brandFont;    // 26 Bold (Titel „Mesh")
+ (UIFont *)keypadFont;   // 26 Regular (Ziffern der PIN-Eingabe)

// Radien (Pillen und Kreise: halbe Höhe)
+ (CGFloat)cardRadius;    // 14  Karten, Knöpfe
+ (CGFloat)fieldRadius;   // 12  Eingabefelder
+ (CGFloat)tileRadius;    // 10  Icon-Kacheln
+ (CGFloat)bubbleRadius;  // 16  Chat-Blasen
+ (CGFloat)sheetRadius;   // 18  Popups
+ (CGFloat)codeRadius;    // 24  Karte um den eigenen QR-Code
+ (CGFloat)topInset;      // 2   Abstand zum oberen Rand (Statusleiste ist ausgeblendet)

@end
