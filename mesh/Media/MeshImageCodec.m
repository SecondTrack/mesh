#import "MeshImageCodec.h"
#import "MeshBase64.h"
#import "MeshNotifications.h"
#import "MeshImageDecoder.h"

static const CGFloat kChatMaxSide = 480, kAvatarSide = 256;
static const CGFloat kChatQuality = 0.4f, kAvatarQuality = 0.5f;

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

// Entschlüsselte Profilbilder; beim Sperren geleert.
static NSCache *PictureCache(void) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 64;
        [[NSNotificationCenter defaultCenter] addObserverForName:MeshWillLockNotification object:nil queue:nil
                                                      usingBlock:^(NSNotification *n) { [cache removeAllObjects]; }];
    });
    return cache;
}

+ (UIImage *)imageFromPicture:(NSString *)picture {
    if (!picture.length) return nil;
    UIImage *hit = [PictureCache() objectForKey:picture];
    if (hit) return hit;
    NSString *b64 = picture;
    if ([picture hasPrefix:@"data:"]) {
        NSRange r = [picture rangeOfString:@";base64,"];
        b64 = (r.location != NSNotFound) ? [picture substringFromIndex:NSMaxRange(r)] : nil;
    } else if ([picture hasPrefix:@"http://"] || [picture hasPrefix:@"https://"]) {
        return nil;
    }
    UIImage *img = [self imageFromData:[MeshBase64 decode:b64] formats:MeshImageJPEG | MeshImagePNG];
    if (img) [PictureCache() setObject:img forKey:picture];
    return img;
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

@end
