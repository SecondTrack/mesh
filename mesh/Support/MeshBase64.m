#import "MeshBase64.h"

@implementation MeshBase64

static const char B64[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

// Beide Richtungen über C-Puffer: am A4 laufen hier ganze Bilder durch, je Zeichen ein
// Objective-C-Aufruf (characterAtIndex:, appendFormat:) kostete pro Bild über 50 ms.
+ (NSString *)encode:(NSData *)data {
    const unsigned char *b = data.bytes; NSUInteger n = data.length;
    NSUInteger len = ((n + 2) / 3) * 4;
    char *o = malloc(len ? len : 1);
    if (!o) return nil;
    NSUInteger k = 0;
    for (NSUInteger i = 0; i < n; i += 3) {
        unsigned int v = (unsigned int)b[i] << 16;
        int have = 1;
        if (i + 1 < n) { v |= (unsigned int)b[i+1] << 8; have = 2; }
        if (i + 2 < n) { v |= b[i+2];                    have = 3; }
        o[k++] = B64[(v >> 18) & 0x3F];
        o[k++] = B64[(v >> 12) & 0x3F];
        o[k++] = have >= 2 ? B64[(v >> 6) & 0x3F] : '=';
        o[k++] = have >= 3 ? B64[v & 0x3F] : '=';
    }
    return [[NSString alloc] initWithBytesNoCopy:o length:k encoding:NSASCIIStringEncoding freeWhenDone:YES];
}

static int b64val(unichar c) {
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '+') return 62;
    if (c == '/') return 63;
    return -1;
}

+ (NSData *)decode:(NSString *)str {
    NSUInteger n = str.length;
    NSMutableData *out = [NSMutableData dataWithLength:n / 4 * 3 + 3];
    unsigned char *o = out.mutableBytes;
    NSUInteger k = 0;
    unsigned int v = 0; int bits = 0;
    unichar chunk[1024];
    for (NSUInteger pos = 0; pos < n; pos += 1024) {
        NSUInteger m = MIN((NSUInteger)1024, n - pos);
        [str getCharacters:chunk range:NSMakeRange(pos, m)];
        for (NSUInteger i = 0; i < m; i++) {
            unichar c = chunk[i];
            if (c == '=') goto done;
            int d = b64val(c);
            if (d < 0) continue;   // Whitespace/Zeilenumbrüche überspringen
            v = (v << 6) | (unsigned int)d; bits += 6;
            if (bits >= 8) { bits -= 8; o[k++] = (v >> bits) & 0xFF; }
        }
    }
done:
    out.length = k;
    return out;
}

@end
