#import "MeshBase64.h"

@implementation MeshBase64

static const char B64[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

+ (NSString *)encode:(NSData *)data {
    const unsigned char *b = data.bytes; NSUInteger n = data.length;
    NSMutableString *out = [NSMutableString stringWithCapacity:((n + 2) / 3) * 4];
    for (NSUInteger i = 0; i < n; i += 3) {
        unsigned int v = b[i] << 16;
        int have = 1;
        if (i + 1 < n) { v |= b[i+1] << 8;  have = 2; }
        if (i + 2 < n) { v |= b[i+2];       have = 3; }
        char c[4] = {
            B64[(v >> 18) & 0x3F], B64[(v >> 12) & 0x3F],
            have >= 2 ? B64[(v >> 6) & 0x3F] : '=',
            have >= 3 ? B64[v & 0x3F] : '='
        };
        [out appendFormat:@"%c%c%c%c", c[0], c[1], c[2], c[3]];
    }
    return out;
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
    NSMutableData *out = [NSMutableData data];
    unsigned int v = 0; int bits = 0;
    NSUInteger n = str.length;
    for (NSUInteger i = 0; i < n; i++) {
        unichar c = [str characterAtIndex:i];
        if (c == '=' ) break;
        int d = b64val(c);
        if (d < 0) continue;   // Whitespace/Zeilenumbrüche überspringen
        v = (v << 6) | d; bits += 6;
        if (bits >= 8) { bits -= 8; unsigned char byte = (v >> bits) & 0xFF; [out appendBytes:&byte length:1]; }
    }
    return out;
}

@end
