#import "MeshImageCodec.h"
#import "MeshBase64.h"
#import "MeshNotifications.h"
#import "MeshImageDecoder.h"

static const CGFloat kChatMaxSide = 480, kAvatarSide = 256;
static const CGFloat kChatQuality = 0.4f, kAvatarQuality = 0.5f;
static const CGFloat kPictureLongest = 1024;   // extreme Seitenverhältnisse: auch die lange Seite begrenzen

// Neu zeichnen mit Faktor scale (< 1), im selben Pixelformat wie MeshDecodeImage (BGRA, vormultipliziert).
// Threadsicher (UIGraphics-Kontexte gehen seit iOS 4 im Hintergrund).
static UIImage *redrawn(UIImage *image, CGFloat scale) {
    CGSize s = CGSizeMake(MAX(1, roundf(image.size.width * scale)), MAX(1, roundf(image.size.height * scale)));
    UIGraphicsBeginImageContextWithOptions(s, NO, 1);
    CGContextSetInterpolationQuality(UIGraphicsGetCurrentContext(), kCGInterpolationHigh);
    [image drawInRect:CGRectMake(0, 0, s.width, s.height)];
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return out ?: image;
}

static NSData *scaledJPEG(UIImage *image, CGFloat scale, CGFloat quality) {
    if (!image) return nil;
    CGSize s = CGSizeMake(roundf(image.size.width * scale), roundf(image.size.height * scale));
    UIGraphicsBeginImageContext(s);
    [image drawInRect:CGRectMake(0, 0, s.width, s.height)];
    UIImage *small = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return UIImageJPEGRepresentation(small, quality);
}

@implementation MeshImageCodec

+ (UIImage *)imageFromData:(NSData *)data formats:(MeshImageFormats)formats {
    // Kopf prüfen (Format, Größe), dann im eigenen Code entpacken: ImageIO sieht keine fremden Dateien
    return [MeshMediaCheck isAcceptableImage:data formats:formats] ? MeshDecodeImage(data, 2048) : nil;
}

+ (UIImage *)shrink:(UIImage *)image longestSide:(CGFloat)side {
    CGFloat longest = MAX(image.size.width, image.size.height) * image.scale;
    if (!image || longest <= side || side <= 0) return image;
    return redrawn(image, side / longest);
}

static NSUInteger pictureCost(UIImage *img) { return (NSUInteger)(img.size.width * img.size.height * img.scale * img.scale * 4); }

// Entschlüsselte Profilbilder; beim Sperren geleert. Nach Pixeln begrenzt (fremde Profilbilder
// dürfen bis 2048 px groß sein, gecacht wird nur die verkleinerte Fassung).
static NSCache *PictureCache(void) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 64;
        cache.totalCostLimit = 8 * 1024 * 1024;
        for (NSString *name in @[MeshWillLockNotification, UIApplicationDidReceiveMemoryWarningNotification])
            [[NSNotificationCenter defaultCenter] addObserverForName:name object:nil queue:nil
                                                          usingBlock:^(NSNotification *n) { [cache removeAllObjects]; }];
    });
    return cache;
}

+ (UIImage *)imageFromPicture:(NSString *)picture {
    if (!picture.length) return nil;
    UIImage *hit = [PictureCache() objectForKey:picture];
    if (hit) return hit;
    UIImage *img = [self decodePicture:picture];
    // Avatare füllen einen Kreis (aspect fill): die kürzere Seite zählt, 256 px reichen für 112 pt Retina
    CGFloat shortest = MIN(img.size.width, img.size.height), longest = MAX(img.size.width, img.size.height);
    if (shortest > 0) {
        CGFloat scale = MIN(kAvatarSide / shortest, kPictureLongest / longest);
        if (scale < 1) img = redrawn(img, scale);
    }
    if (img) [PictureCache() setObject:img forKey:picture cost:pictureCost(img)];
    return img;
}

+ (UIImage *)imageFromPicture:(NSString *)picture longestSide:(CGFloat)side {
    return [self shrink:[self decodePicture:picture] longestSide:side];
}

+ (UIImage *)decodePicture:(NSString *)picture {
    if (!picture.length) return nil;
    NSString *b64 = picture;
    if ([picture hasPrefix:@"data:"]) {
        NSRange r = [picture rangeOfString:@";base64,"];
        b64 = (r.location != NSNotFound) ? [picture substringFromIndex:NSMaxRange(r)] : nil;
    } else if ([picture hasPrefix:@"http://"] || [picture hasPrefix:@"https://"]) {
        return nil;
    }
    return [self imageFromData:[MeshBase64 decode:b64] formats:MeshImageJPEG | MeshImagePNG];
}

+ (NSString *)pictureFromJPEG:(NSData *)jpeg { return jpeg.length ? [MeshBase64 encode:jpeg] : @""; }

+ (NSData *)jpegForChat:(UIImage *)image {
    CGFloat longest = MAX(image.size.width, image.size.height);
    return scaledJPEG(image, longest > 0 ? MIN(1.0f, kChatMaxSide / longest) : 1, kChatQuality);
}

+ (NSData *)jpegForAvatar:(UIImage *)image {
    CGFloat shortest = MIN(image.size.width, image.size.height);
    return scaledJPEG(image, shortest > 0 ? kAvatarSide / shortest : 1, kAvatarQuality);
}

// Gruppenbild: die Mitte quadratisch ausschneiden, auf 256 × 256 skalieren, Qualität wie beim Profilbild;
// wird es (selten) größer als 64 KB, mit geringerer Qualität noch einmal.
+ (NSData *)jpegForGroupPicture:(UIImage *)image {
    CGFloat w = image.size.width, h = image.size.height, side = MIN(w, h);
    if (!image || side <= 0) return nil;
    CGFloat scale = kAvatarSide / side;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(kAvatarSide, kAvatarSide), YES, 1);
    CGContextSetInterpolationQuality(UIGraphicsGetCurrentContext(), kCGInterpolationHigh);
    [image drawInRect:CGRectMake((kAvatarSide - w * scale) / 2, (kAvatarSide - h * scale) / 2, w * scale, h * scale)];
    UIImage *square = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    for (CGFloat q = kAvatarQuality; q > 0.15f; q -= 0.15f) {
        NSData *jpeg = UIImageJPEGRepresentation(square, q);
        if (jpeg.length && jpeg.length <= 64 * 1024) return jpeg;
    }
    return nil;
}

@end
