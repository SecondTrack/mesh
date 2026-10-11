#import "MeshMediaCheck.h"

const int MeshImageMaxSide = 2048;
const int MeshImageMaxPixels = 2048 * 1536;

static int be16(const uint8_t *p) { return (p[0] << 8) | p[1]; }
static uint32_t be32(const uint8_t *p) { return ((uint32_t)p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3]; }

// JPEG: Marker-Segmente bis zum Start-of-Frame laufen (SOF0–SOF15 außer DHT/JPG/DAC).
static CGSize jpegSize(const uint8_t *b, NSUInteger n) {
    if (n < 4 || b[0] != 0xFF || b[1] != 0xD8) return CGSizeZero;
    NSUInteger i = 2;
    while (i + 4 <= n) {
        if (b[i] != 0xFF) return CGSizeZero;
        uint8_t m = b[i + 1];
        if (m == 0xFF) { i++; continue; }                         // Füllbyte
        if (m == 0xD8 || m == 0x01 || (m >= 0xD0 && m <= 0xD7)) { i += 2; continue; }   // ohne Länge
        if (m == 0xD9 || m == 0xDA) return CGSizeZero;            // Ende/Scan vor dem Frame-Kopf
        int len = be16(b + i + 2);
        if (len < 2 || i + 2 + len > n) return CGSizeZero;
        BOOL sof = m >= 0xC0 && m <= 0xCF && m != 0xC4 && m != 0xC8 && m != 0xCC;
        if (sof) {
            if (len < 7) return CGSizeZero;
            return CGSizeMake(be16(b + i + 7), be16(b + i + 5));   // Breite, Höhe
        }
        i += 2 + len;
    }
    return CGSizeZero;
}

// PNG: Signatur, dann IHDR als erster Chunk.
static CGSize pngSize(const uint8_t *b, NSUInteger n) {
    static const uint8_t sig[8] = { 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A };
    if (n < 24 || memcmp(b, sig, 8) || memcmp(b + 12, "IHDR", 4)) return CGSizeZero;
    uint32_t w = be32(b + 16), h = be32(b + 20);
    if (w > 0xFFFF || h > 0xFFFF) return CGSizeZero;
    return CGSizeMake(w, h);
}

@implementation MeshMediaCheck

+ (CGSize)imageSize:(NSData *)data formats:(MeshImageFormats)formats {
    const uint8_t *b = data.bytes; NSUInteger n = data.length;
    if ((formats & MeshImageJPEG) && n >= 2 && b[0] == 0xFF && b[1] == 0xD8) return jpegSize(b, n);
    if ((formats & MeshImagePNG) && n >= 8 && b[0] == 0x89) return pngSize(b, n);
    return CGSizeZero;
}

+ (BOOL)isAcceptableImage:(NSData *)data formats:(MeshImageFormats)formats {
    CGSize s = [self imageSize:data formats:formats];
    int w = (int)s.width, h = (int)s.height;
    return w > 0 && h > 0 && w <= MeshImageMaxSide && h <= MeshImageMaxSide && w * h <= MeshImageMaxPixels;
}

// M4A: oberste Boxen lückenlos innerhalb der Daten, ftyp zuerst, moov vorhanden.
static BOOL isM4A(const uint8_t *b, NSUInteger n) {
    if (n < 16 || memcmp(b + 4, "ftyp", 4)) return NO;
    BOOL moov = NO;
    NSUInteger i = 0;
    while (i < n) {
        if (n - i < 8) return NO;
        uint64_t size = be32(b + i), header = 8;
        if (size == 1) {                                     // 64-Bit-Größe
            if (n - i < 16) return NO;
            size = ((uint64_t)be32(b + i + 8) << 32) | be32(b + i + 12);
            header = 16;
        } else if (size == 0) {
            size = n - i;                                    // bis zum Ende
        }
        if (size < header || size > n - i) return NO;
        if (!memcmp(b + i + 4, "moov", 4)) moov = YES;
        i += (NSUInteger)size;
    }
    return moov;
}

// AAC-ADTS: lückenlose Folge gültiger Frame-Köpfe (Sync, Layer 0, Länge ≥ Kopf).
static BOOL isADTS(const uint8_t *b, NSUInteger n) {
    if (n < 7) return NO;
    NSUInteger i = 0;
    while (i < n) {
        if (n - i < 7 || b[i] != 0xFF || (b[i + 1] & 0xF6) != 0xF0) return NO;
        NSUInteger len = ((b[i + 3] & 0x03) << 11) | (b[i + 4] << 3) | (b[i + 5] >> 5);
        if (len < 7 || len > n - i) return NO;
        i += len;
    }
    return YES;
}

+ (BOOL)isAcceptableAudio:(NSData *)data {
    return isM4A(data.bytes, data.length) || isADTS(data.bytes, data.length);
}

@end
