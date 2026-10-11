#import "MeshQR.h"

#include "qrcodegen.h"

@implementation MeshQR

// Fehlerkorrektur L: ein Code auf einem Bildschirm wird nicht verschmutzt oder geknickt, die Reserve
// von M kostet nur Dichte (Code mit Signal-Paket: Version 11 statt 13, 61 statt 69 Module).
// Module liegen ganzzahlig auf Bildschirmpixeln: keine weichen Kanten für die Kamera.
+ (UIImage *)imageForString:(NSString *)s sizePx:(CGFloat)px module:(UIColor *)fg background:(UIColor *)bg {
    uint8_t qr[qrcodegen_BUFFER_LEN_MAX];
    uint8_t tmp[qrcodegen_BUFFER_LEN_MAX];
    if (!qrcodegen_encodeText([s UTF8String], tmp, qr,
                              qrcodegen_Ecc_LOW, qrcodegen_VERSION_MIN, qrcodegen_VERSION_MAX,
                              qrcodegen_Mask_AUTO, true)) {
        return nil;
    }
    int n = qrcodegen_getSize(qr);
    int quiet = 4;                                  // Ruhezone laut Standard
    int total = n + 2 * quiet;
    CGFloat scale = [UIScreen mainScreen].scale;
    int side = (int)(px * scale);                   // in echten Pixeln
    int m = side / total;                           // ganze Pixel je Modul
    if (m < 1) return nil;
    int off = (side - m * total) / 2;

    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), YES, 1);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(ctx, bg.CGColor);
    CGContextFillRect(ctx, CGRectMake(0, 0, side, side));
    CGContextSetFillColorWithColor(ctx, fg.CGColor);
    for (int y = 0; y < n; y++)
        for (int x = 0; x < n; x++)
            if (qrcodegen_getModule(qr, x, y))
                CGContextFillRect(ctx, CGRectMake(off + (x + quiet) * m, off + (y + quiet) * m, m, m));
    UIImage *raw = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [UIImage imageWithCGImage:raw.CGImage scale:scale orientation:UIImageOrientationUp];
}

@end
