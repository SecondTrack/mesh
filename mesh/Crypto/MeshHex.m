#import "MeshHex.h"

@implementation MeshHex

+ (NSString *)encode:(NSData *)data {
    if (!data) return nil;
    const unsigned char *b = data.bytes;
    NSUInteger n = data.length;
    NSMutableString *s = [NSMutableString stringWithCapacity:n * 2];
    static const char *hx = "0123456789abcdef";
    for (NSUInteger i = 0; i < n; i++) {
        [s appendFormat:@"%c%c", hx[(b[i] >> 4) & 0xF], hx[b[i] & 0xF]];
    }
    return s;
}

static int nib(unichar c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

+ (NSData *)decode:(NSString *)hex {
    if (!hex || (hex.length % 2) != 0) return nil;
    NSUInteger n = hex.length / 2;
    NSMutableData *d = [NSMutableData dataWithLength:n];
    unsigned char *out = d.mutableBytes;
    for (NSUInteger i = 0; i < n; i++) {
        int hi = nib([hex characterAtIndex:i * 2]);
        int lo = nib([hex characterAtIndex:i * 2 + 1]);
        if (hi < 0 || lo < 0) return nil;
        out[i] = (unsigned char)((hi << 4) | lo);
    }
    return d;
}

@end
