#import "MeshBech32.h"

static const char *CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l";

// BIP-173: Gesamtlänge höchstens 90, Präfix (hrp) 1–83 Zeichen aus ASCII 33–126.
// Alle Puffer unten sind auf diese Grenzen ausgelegt.
enum { kMaxLen = 90, kMaxHrp = 83 };

static BOOL validHrp(const char *h, size_t hlen) {
    if (hlen < 1 || hlen > kMaxHrp) return NO;
    for (size_t i = 0; i < hlen; i++) if (h[i] < 33 || h[i] > 126) return NO;
    return YES;
}

static uint32_t polymod(const uint8_t *values, size_t len) {
    uint32_t chk = 1;
    static const uint32_t GEN[5] = {0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3};
    for (size_t i = 0; i < len; i++) {
        uint8_t top = chk >> 25;
        chk = (chk & 0x1ffffff) << 5 ^ values[i];
        for (int j = 0; j < 5; j++) if ((top >> j) & 1) chk ^= GEN[j];
    }
    return chk;
}

// hrp-Expansion für die Prüfsumme.
static void hrpExpand(const char *hrp, size_t hlen, uint8_t *out, size_t *outLen) {
    size_t i = 0;
    for (; i < hlen; i++) out[i] = (uint8_t)(hrp[i] >> 5);
    out[i++] = 0;
    for (size_t k = 0; k < hlen; k++) out[i++] = (uint8_t)(hrp[k] & 31);
    *outLen = i;
}

// convertbits (frombits -> tobits), pad optional. Schreibt in out, gibt Länge zurück (-1 = Fehler).
static int convertBits(const uint8_t *in, size_t inLen, int fromBits, int toBits, int pad,
                       uint8_t *out, size_t outCap) {
    uint32_t acc = 0; int bits = 0; size_t o = 0;
    uint32_t maxv = (1u << toBits) - 1;
    for (size_t i = 0; i < inLen; i++) {
        if (in[i] >> fromBits) return -1;
        acc = (acc << fromBits) | in[i];
        bits += fromBits;
        while (bits >= toBits) {
            bits -= toBits;
            if (o >= outCap) return -1;
            out[o++] = (acc >> bits) & maxv;
        }
    }
    if (pad) {
        if (bits > 0) { if (o >= outCap) return -1; out[o++] = (acc << (toBits - bits)) & maxv; }
    } else if (bits >= fromBits || ((acc << (toBits - bits)) & maxv)) {
        return -1;
    }
    return (int)o;
}

@implementation MeshBech32

+ (NSString *)encodeHrp:(NSString *)hrp data:(NSData *)data {
    const char *h = hrp.UTF8String; size_t hlen = h ? strlen(h) : 0;
    if (!validHrp(h, hlen)) return nil;
    // 8-bit -> 5-bit
    uint8_t five[kMaxLen]; int flen = convertBits(data.bytes, data.length, 8, 5, 1, five, sizeof(five));
    if (flen < 0 || hlen + 1 + (size_t)flen + 6 > kMaxLen) return nil;

    // Checksum-Input: hrpExpand + data + 6*0
    uint8_t chkin[2 * kMaxLen]; size_t ci = 0; hrpExpand(h, hlen, chkin, &ci);
    for (int i = 0; i < flen; i++) chkin[ci++] = five[i];
    for (int i = 0; i < 6; i++) chkin[ci++] = 0;
    uint32_t mod = polymod(chkin, ci) ^ 1;
    uint8_t chk[6];
    for (int i = 0; i < 6; i++) chk[i] = (mod >> (5 * (5 - i))) & 31;

    NSMutableString *s = [NSMutableString stringWithUTF8String:h];
    [s appendString:@"1"];
    for (int i = 0; i < flen; i++) [s appendFormat:@"%c", CHARSET[five[i]]];
    for (int i = 0; i < 6; i++)    [s appendFormat:@"%c", CHARSET[chk[i]]];
    return s;
}

+ (NSData *)decode:(NSString *)str hrp:(NSString **)hrpOut {
    if (str.length > kMaxLen) return nil;
    // Gemischte Groß-/Kleinschreibung ist laut BIP-173 ungültig.
    NSString *low = [str lowercaseString];
    if (![str isEqualToString:low] && ![str isEqualToString:[str uppercaseString]]) return nil;
    NSData *bytes = [low dataUsingEncoding:NSASCIIStringEncoding];
    if (!bytes) return nil;
    const char *s = bytes.bytes; size_t slen = bytes.length;
    if (slen > kMaxLen || memchr(s, 0, slen)) return nil;
    // letzte '1' trennt hrp von data
    long sep = -1;
    for (long i = (long)slen - 1; i >= 0; i--) if (s[i] == '1') { sep = i; break; }
    if (sep < 1 || (size_t)(sep + 7) > slen) return nil;

    size_t hlen = (size_t)sep;
    if (!validHrp(s, hlen)) return nil;
    size_t dlen = slen - sep - 1;
    uint8_t vals[kMaxLen];
    for (size_t i = 0; i < dlen; i++) {
        const char *p = memchr(CHARSET, s[sep + 1 + i], 32);
        if (!p) return nil;
        vals[i] = (uint8_t)(p - CHARSET);
    }
    // Prüfsumme verifizieren
    uint8_t chkin[2 * kMaxLen]; size_t ci = 0; hrpExpand(s, hlen, chkin, &ci);
    for (size_t i = 0; i < dlen; i++) chkin[ci++] = vals[i];
    if (polymod(chkin, ci) != 1) return nil;

    // 5-bit -> 8-bit (ohne die 6 Prüfsummen-Zeichen), kein pad
    uint8_t out[kMaxLen]; int olen = convertBits(vals, dlen - 6, 5, 8, 0, out, sizeof(out));
    if (olen < 0) return nil;
    if (hrpOut) *hrpOut = [[NSString alloc] initWithBytes:s length:hlen encoding:NSUTF8StringEncoding];
    return [NSData dataWithBytes:out length:olen];
}

@end
