// Farben und Schriften. Schriften: HelveticaNeue (System) und Menlo (Festbreite).
// Die Farbwerte entsprechen der Android-App, damit beide gleich aussehen.
#import "MeshTheme.h"

@implementation MeshTheme

+ (UIColor *)bg          { return MESH_RGB(0x0A0F0E); }
+ (UIColor *)surface     { return MESH_RGB(0x111A17); }
+ (UIColor *)surfaceHi   { return MESH_RGB(0x18231F); }
+ (UIColor *)field       { return MESH_RGB(0x16211D); }
+ (UIColor *)line        { return MESH_RGB(0x213029); }
+ (UIColor *)accent      { return MESH_RGB(0x2FE6A8); }
+ (UIColor *)accentDim   { return MESH_RGB(0x1C8F6B); }
+ (UIColor *)accentDeep  { return MESH_RGB(0x0F3A2E); }
+ (UIColor *)ink         { return MESH_RGB(0xE8F0ED); }
+ (UIColor *)muted       { return MESH_RGB(0x8A9A94); }
+ (UIColor *)faint       { return MESH_RGB(0x5A6B65); }
+ (UIColor *)bubbleMeInk { return MESH_RGB(0xE6FBF2); }
+ (UIColor *)danger      { return MESH_RGB(0xFF6B6B); }

// Kleiner Helfer: benannten Font versuchen, sonst System-Fallback.
+ (UIFont *)font:(NSString *)name size:(CGFloat)sz fallbackBold:(BOOL)bold {
    UIFont *f = [UIFont fontWithName:name size:sz];
    if (f) return f;
    return bold ? [UIFont boldSystemFontOfSize:sz] : [UIFont systemFontOfSize:sz];
}

+ (UIFont *)titleFont   { return [self font:@"HelveticaNeue-Bold"   size:20.0f fallbackBold:YES]; }
+ (UIFont *)nameFont    { return [self font:@"HelveticaNeue-Medium" size:16.0f fallbackBold:YES]; }  // SemiBold ~ Medium
+ (UIFont *)bodyFont    { return [self font:@"HelveticaNeue"        size:15.0f fallbackBold:NO];  }
+ (UIFont *)previewFont { return [self font:@"HelveticaNeue"        size:14.0f fallbackBold:NO];  }
+ (UIFont *)labelFont   { return [self font:@"HelveticaNeue-Medium" size:11.0f fallbackBold:YES]; }
+ (UIFont *)timeFont    { return [self font:@"HelveticaNeue"        size:11.0f fallbackBold:NO];  }
+ (UIFont *)monoFont    { return [self font:@"Menlo-Regular"        size:12.0f fallbackBold:NO];  }
+ (UIFont *)monoBigFont { return [self font:@"Menlo"               size:14.0f fallbackBold:NO];  }
+ (UIFont *)keypadFont  { return [UIFont systemFontOfSize:26.0f]; }
+ (UIFont *)brandFont   { return [self font:@"HelveticaNeue-Bold"   size:26.0f fallbackBold:YES]; }

+ (CGFloat)cardRadius  { return 14.0f; }
+ (CGFloat)fieldRadius { return 12.0f; }
+ (CGFloat)tileRadius  { return 10.0f; }
+ (CGFloat)bubbleRadius{ return 16.0f; }
+ (CGFloat)sheetRadius { return 18.0f; }
+ (CGFloat)codeRadius  { return 24.0f; }
+ (CGFloat)topInset    { return 2.0f; }

@end
