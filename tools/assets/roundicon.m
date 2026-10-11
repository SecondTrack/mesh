// roundicon.m — backt gerundete Ecken (transparent außen) in ein PNG. Aufruf: roundicon in.png out.png ratio
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import <CoreServices/CoreServices.h>

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 4) { printf("usage: roundicon in out ratio\n"); return 1; }
        CFURLRef inUrl = CFURLCreateWithFileSystemPath(NULL, (CFStringRef)@(argv[1]), kCFURLPOSIXPathStyle, false);
        CGImageSourceRef src = CGImageSourceCreateWithURL(inUrl, NULL);
        CGImageRef img = CGImageSourceCreateImageAtIndex(src, 0, NULL);
        size_t W = CGImageGetWidth(img), H = CGImageGetHeight(img);
        CGFloat r = W * atof(argv[3]);
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
        CGContextRef ctx = CGBitmapContextCreate(NULL, W, H, 8, 0, cs, kCGImageAlphaPremultipliedLast);
        CGMutablePathRef path = CGPathCreateMutable();
        CGPathMoveToPoint(path, NULL, r, 0);
        CGPathAddArcToPoint(path, NULL, W, 0, W, r, r);
        CGPathAddArcToPoint(path, NULL, W, H, W - r, H, r);
        CGPathAddArcToPoint(path, NULL, 0, H, 0, H - r, r);
        CGPathAddArcToPoint(path, NULL, 0, 0, r, 0, r);
        CGPathCloseSubpath(path);
        CGContextAddPath(ctx, path); CGContextClip(ctx);
        CGContextDrawImage(ctx, CGRectMake(0, 0, W, H), img);
        CGImageRef out = CGBitmapContextCreateImage(ctx);
        CFURLRef outUrl = CFURLCreateWithFileSystemPath(NULL, (CFStringRef)@(argv[2]), kCFURLPOSIXPathStyle, false);
        CGImageDestinationRef dest = CGImageDestinationCreateWithURL(outUrl, kUTTypePNG, 1, NULL);
        CGImageDestinationAddImage(dest, out, NULL);
        CGImageDestinationFinalize(dest);
        printf("rounded %s (%zux%zu, r=%.1f) -> %s\n", argv[1], W, H, r, argv[2]);
    }
    return 0;
}
