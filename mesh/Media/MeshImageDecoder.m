#import "MeshImageDecoder.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"
#pragma clang diagnostic ignored "-Wsign-compare"
#pragma clang diagnostic ignored "-Wunused-but-set-variable"
#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_JPEG
#define STBI_ONLY_PNG
#define STBI_NO_STDIO
#define STBI_NO_LINEAR
#define STBI_NO_HDR
#define STBI_NO_FAILURE_STRINGS
#define STBI_NO_THREAD_LOCALS          // iOS 5/6 kennt kein thread_local; Fehlertexte sind abgeschaltet
#define STBI_MAX_DIMENSIONS 4096
#include "stb_image.h"
#pragma clang diagnostic pop

static void freePixels(void *info, const void *data, size_t size) { stbi_image_free((void *)data); }

UIImage *MeshDecodeImage(NSData *data, int maxSide) {
    if (data.length < 8 || data.length > INT_MAX) return nil;
    int w = 0, h = 0, n = 0;
    // Maße zuerst aus dem Kopf: zu große Bilder gar nicht erst entpacken (Speicher eines 128-MB-Geräts)
    if (!stbi_info_from_memory(data.bytes, (int)data.length, &w, &h, &n) || w <= 0 || h <= 0 || w > maxSide || h > maxSide) return nil;
    unsigned char *px = stbi_load_from_memory(data.bytes, (int)data.length, &w, &h, &n, 4);
    if (!px) return nil;
    if (w <= 0 || h <= 0 || w > maxSide || h > maxSide) { stbi_image_free(px); return nil; }
    size_t len = (size_t)w * (size_t)h * 4;
    // In das Format bringen, das iOS ohne Umrechnung zeichnet (BGRA, Alpha vormultipliziert):
    // sonst rechnet Core Animation das Bild bei jedem Zeichnen um, und Chats ruckeln.
    for (size_t i = 0; i < len; i += 4) {
        unsigned r = px[i], g = px[i + 1], b = px[i + 2], a = px[i + 3];
        if (a != 255) { r = (r * a + 127) / 255; g = (g * a + 127) / 255; b = (b * a + 127) / 255; }
        px[i] = (unsigned char)b; px[i + 1] = (unsigned char)g; px[i + 2] = (unsigned char)r;
    }
    CGDataProviderRef prov = CGDataProviderCreateWithData(NULL, px, len, freePixels);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGImageRef cg = CGImageCreate((size_t)w, (size_t)h, 8, 32, (size_t)w * 4, cs,
                                  (CGBitmapInfo)kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little, prov, NULL, false, kCGRenderingIntentDefault);
    CGColorSpaceRelease(cs); CGDataProviderRelease(prov);
    if (!cg) return nil;
    UIImage *img = [UIImage imageWithCGImage:cg];
    CGImageRelease(cg);
    return img;
}
