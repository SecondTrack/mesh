// Format- und Größenprüfung fremder Bilder und Audiodaten.
#import "MeshTest.h"
#import <ImageIO/ImageIO.h>
#import <CoreServices/CoreServices.h>
#import "MeshMediaCheck.h"

// Echtes Bild mit ImageIO (System) erzeugen.
static NSData *makeImage(int w, int h, CFStringRef type) {
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, 0, cs, kCGImageAlphaPremultipliedLast);
    CGContextSetRGBFillColor(ctx, 0.2, 0.6, 0.4, 1); CGContextFillRect(ctx, CGRectMake(0, 0, w, h));
    CGImageRef img = CGBitmapContextCreateImage(ctx);
    NSMutableData *d = [NSMutableData data];
    CGImageDestinationRef dst = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)d, type, 1, NULL);
    CGImageDestinationAddImage(dst, img, NULL); CGImageDestinationFinalize(dst);
    CFRelease(dst); CGImageRelease(img); CGContextRelease(ctx); CGColorSpaceRelease(cs);
    return d;
}

int main(void) { @autoreleasepool {
    MeshImageFormats both = MeshImageJPEG | MeshImagePNG;
    NSData *jpg = makeImage(640, 480, kUTTypeJPEG), *png = makeImage(57, 57, kUTTypePNG);
    check(CGSizeEqualToSize([MeshMediaCheck imageSize:jpg formats:both], CGSizeMake(640, 480)), "jpeg size from header");
    check(CGSizeEqualToSize([MeshMediaCheck imageSize:png formats:both], CGSizeMake(57, 57)), "png size from header");
    check([MeshMediaCheck isAcceptableImage:jpg formats:MeshImageJPEG], "jpeg accepted");
    check(![MeshMediaCheck isAcceptableImage:png formats:MeshImageJPEG], "png refused where only jpeg allowed");
    check(![MeshMediaCheck isAcceptableImage:makeImage(32, 32, kUTTypeTIFF) formats:both], "tiff refused");
    check(![MeshMediaCheck isAcceptableImage:makeImage(32, 32, kUTTypeGIF) formats:both], "gif refused");
    check(![MeshMediaCheck isAcceptableImage:makeImage(32, 32, kUTTypeBMP) formats:both], "bmp refused");
    check(![MeshMediaCheck isAcceptableImage:makeImage(3000, 100, kUTTypeJPEG) formats:both], "side > 2048");
    check(![MeshMediaCheck isAcceptableImage:makeImage(2048, 2048, kUTTypeJPEG) formats:both], "over 3.1 MP");
    check([MeshMediaCheck isAcceptableImage:makeImage(2048, 1536, kUTTypePNG) formats:both], "at the limits");

    // Bild-Bombe: echtes JPEG, im Kopf 60000×60000 eingetragen
    NSMutableData *bomb = [jpg mutableCopy]; uint8_t *b = bomb.mutableBytes;
    for (NSUInteger i = 2; i + 9 < bomb.length; ) {
        if (b[i] == 0xFF && b[i+1] == 0xC0) { b[i+5] = 0xEA; b[i+6] = 0x60; b[i+7] = 0xEA; b[i+8] = 0x60; break; }
        i += 2 + ((b[i+2] << 8) | b[i+3]);
    }
    check(![MeshMediaCheck isAcceptableImage:bomb formats:both], "decompression bomb");

    // Kaputtes: abgeschnitten, Längenfeld zeigt hinter das Ende, Müll, leer
    check(![MeshMediaCheck isAcceptableImage:[jpg subdataWithRange:NSMakeRange(0, 20)] formats:both], "truncated jpeg");
    NSData *evil = [NSData dataWithBytes:"\xFF\xD8\xFF\xE0\xFF\xFF" length:6];
    check(![MeshMediaCheck isAcceptableImage:evil formats:both], "segment length past end");
    check(![MeshMediaCheck isAcceptableImage:[NSData dataWithBytes:"\xFF\xD8" length:2] formats:both], "only SOI");
    check(![MeshMediaCheck isAcceptableImage:[NSData data] formats:both], "empty");
    NSMutableData *junk = [NSMutableData dataWithLength:5000];
    for (int i = 0; i < 2000; i++) {   // Fuzz: zufällige Bytes hinter echtem SOI dürfen nie abstürzen
        arc4random_buf(junk.mutableBytes, junk.length); ((uint8_t *)junk.mutableBytes)[0] = 0xFF; ((uint8_t *)junk.mutableBytes)[1] = 0xD8;
        [MeshMediaCheck imageSize:junk formats:both];
    }
    check(YES, "fuzz survived");

    // Audio
    NSData *m4a = [NSData dataWithBytes:"\x00\x00\x00\x10" "ftypM4A " "\x00\x00\x00\x00" "\x00\x00\x00\x08" "moov" "\x00\x00\x00\x0C" "mdat" "abcd" length:36];
    check([MeshMediaCheck isAcceptableAudio:m4a], "m4a structure");
    NSMutableData *liar = [m4a mutableCopy]; ((uint8_t *)liar.mutableBytes)[3] = 0xFF;   // ftyp behauptet 255 Byte
    check(![MeshMediaCheck isAcceptableAudio:liar], "box size past end");
    check(![MeshMediaCheck isAcceptableAudio:[m4a subdataWithRange:NSMakeRange(0, 16)]], "m4a without moov");
    check(![MeshMediaCheck isAcceptableAudio:[NSData dataWithBytes:"\x00\x00\x00\x1c" "ftypM4A " length:12]], "only ftyp prefix");
    NSData *adts = [NSData dataWithBytes:"\xFF\xF1\x50\x80\x00\xFF\xFC" "\xFF\xF1\x50\x80\x00\xFF\xFC" length:14];
    check([MeshMediaCheck isAcceptableAudio:adts], "adts frames");
    check(![MeshMediaCheck isAcceptableAudio:[NSData dataWithBytes:"\xFF\xF1\x50\x80\x02\x1F\xFC" length:7]], "adts length past end");
    check(![MeshMediaCheck isAcceptableAudio:[NSData dataWithBytes:"RIFF\x00\x00\x00\x00WAVE" length:12]], "wav refused");
    check(![MeshMediaCheck isAcceptableAudio:[NSData dataWithBytes:"ID3\x03" length:4]], "mp3 refused");

    return testsDone();
}}
