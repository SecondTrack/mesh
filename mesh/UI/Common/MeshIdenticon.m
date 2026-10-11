#import "MeshIdenticon.h"

@implementation MeshIdenticon

// FNV-1a 64-bit über den Seed → stabiler Hash.
static unsigned long long fnv(NSString *seed) {
    unsigned long long h = 1469598103934665603ULL;
    const char *s = [(seed ?: @"") UTF8String];
    while (s && *s) { h ^= (unsigned char)*s++; h *= 1099511628211ULL; }
    return h;
}

+ (void)drawSeed:(NSString *)seed inRect:(CGRect)rect context:(CGContextRef)ctx {
    unsigned long long h = fnv(seed);

    // Vordergrundfarbe aus dem Hash, in der Mesh-Mint/Teal-Familie gehalten.
    CGFloat t = (CGFloat)((h >> 40) & 0xFF) / 255.0f;
    UIColor *fg = [UIColor colorWithRed:0.12f + 0.16f * t
                                  green:0.55f + 0.30f * t
                                   blue:0.48f + 0.22f * t alpha:1.0f];
    UIColor *bg = [UIColor colorWithRed:0.09f green:0.13f blue:0.12f alpha:1.0f]; // ~ surfaceHi

    // Kreis clippen + Hintergrund.
    CGContextSaveGState(ctx);
    CGContextAddEllipseInRect(ctx, rect);
    CGContextClip(ctx);
    CGContextSetFillColorWithColor(ctx, bg.CGColor);
    CGContextFillRect(ctx, rect);

    // 5×5-Raster, linke 3 Spalten aus Hash-Bits, rechts gespiegelt.
    CGFloat cell = rect.size.width / 5.0f;
    CGContextSetFillColorWithColor(ctx, fg.CGColor);
    for (int col = 0; col < 3; col++) {
        for (int row = 0; row < 5; row++) {
            int bit = (h >> (col * 5 + row)) & 1ULL;
            if (!bit) continue;
            int cols[2] = { col, 4 - col };
            int nn = (col == 2) ? 1 : 2;   // Mittelspalte nicht doppelt
            for (int k = 0; k < nn; k++) {
                CGRect r = CGRectMake(rect.origin.x + cols[k] * cell,
                                      rect.origin.y + row * cell, cell + 0.5f, cell + 0.5f);
                CGContextFillRect(ctx, r);
            }
        }
    }
    CGContextRestoreGState(ctx);
}

@end
