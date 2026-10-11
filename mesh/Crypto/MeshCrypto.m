#import "MeshCrypto.h"
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>
#import <CommonCrypto/CommonCryptor.h>
#import <CommonCrypto/CommonKeyDerivation.h>
#import <CommonCrypto/CommonHMAC.h>
#import "MeshMemory.h"
#include <dlfcn.h>

@implementation MeshCrypto

+ (NSData *)sha256:(NSData *)data {
    unsigned char out[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, out);
    return [NSData dataWithBytes:out length:CC_SHA256_DIGEST_LENGTH];
}

+ (NSData *)sha512:(NSData *)data {
    unsigned char out[CC_SHA512_DIGEST_LENGTH];
    CC_SHA512(data.bytes, (CC_LONG)data.length, out);
    return [NSData dataWithBytes:out length:CC_SHA512_DIGEST_LENGTH];
}

+ (NSData *)hmacSHA256:(NSData *)data key:(NSData *)key {
    NSMutableData *h = [NSMutableData dataWithLength:CC_SHA256_DIGEST_LENGTH];   // mit MeshWipe löschbar
    CCHmac(kCCHmacAlgSHA256, key.bytes, key.length, data.bytes, data.length, h.mutableBytes);
    return h;
}

+ (NSData *)hkdfExtractSalt:(NSData *)salt ikm:(NSData *)ikm {
    return [self hmacSHA256:ikm key:salt];
}

+ (NSData *)hkdfExpand:(NSData *)prk info:(NSData *)info length:(NSUInteger)length {
    if (length > 255 * CC_SHA256_DIGEST_LENGTH) return nil;
    NSMutableData *out = [NSMutableData dataWithCapacity:length];
    NSMutableData *t = [NSMutableData data];
    for (uint8_t i = 1; out.length < length; i++) {
        NSMutableData *input = [t mutableCopy];
        [input appendData:info];
        [input appendBytes:&i length:1];
        MeshWipe(t);
        t = (NSMutableData *)[self hmacSHA256:input key:prk];
        MeshWipe(input);
        [out appendBytes:t.bytes length:MIN(t.length, length - out.length)];
    }
    MeshWipe(t);
    return out;
}

+ (BOOL)constantTimeEqual:(NSData *)a to:(NSData *)b {
    if (a.length != b.length) return NO;
    const uint8_t *x = a.bytes, *y = b.bytes;
    uint8_t diff = 0;
    for (NSUInteger i = 0; i < a.length; i++) diff |= x[i] ^ y[i];
    return diff == 0;
}

+ (NSData *)sha1:(NSData *)data {
    unsigned char h[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(data.bytes, (CC_LONG)data.length, h);
    return [NSData dataWithBytes:h length:sizeof(h)];
}

// PBKDF2-HMAC-SHA256 (RFC 8018), ein Block à 32 Byte. Eigene Umsetzung für iOS 4, wo
// CCKeyDerivationPBKDF fehlt; muss bitgleich zu CommonCrypto sein (tests/crypto_test.m).
NSData *MeshPBKDF2SHA256Portable(NSData *pw, NSData *salt, int iters) {
    if (iters < 1) return nil;
    CCHmacContext base, ctx;
    CCHmacInit(&base, kCCHmacAlgSHA256, pw.bytes, pw.length);   // Schlüssel-Pads einmal vorberechnen
    uint8_t u[CC_SHA256_DIGEST_LENGTH], t[CC_SHA256_DIGEST_LENGTH];
    const uint8_t blockIndex[4] = { 0, 0, 0, 1 };
    memcpy(&ctx, &base, sizeof ctx);
    CCHmacUpdate(&ctx, salt.bytes, salt.length);
    CCHmacUpdate(&ctx, blockIndex, sizeof blockIndex);
    CCHmacFinal(&ctx, u);
    memcpy(t, u, sizeof t);
    for (int i = 1; i < iters; i++) {
        memcpy(&ctx, &base, sizeof ctx);
        CCHmacUpdate(&ctx, u, sizeof u);
        CCHmacFinal(&ctx, u);
        for (int k = 0; k < CC_SHA256_DIGEST_LENGTH; k++) t[k] ^= u[k];
    }
    NSData *out = [NSMutableData dataWithBytes:t length:sizeof t];   // mit MeshWipe löschbar
    memset(u, 0, sizeof u); memset(t, 0, sizeof t);
    memset(&base, 0, sizeof base); memset(&ctx, 0, sizeof ctx);
    return out;
}

+ (NSData *)pbkdf2:(NSString *)pin salt:(NSData *)salt iters:(int)iters {
    NSData *pw = [pin dataUsingEncoding:NSUTF8StringEncoding];
    // Ab iOS 5 die Systemfunktion (schneller), davor die eigene. Auflösung zur Laufzeit,
    // damit ein iOS-4-Gerät beim Start nicht an einem fehlenden Symbol scheitert.
    typedef int (*PBKDFFn)(CCPBKDFAlgorithm, const char *, size_t, const uint8_t *, size_t,
                           CCPseudoRandomAlgorithm, uint, uint8_t *, size_t);
    static PBKDFFn sys; static dispatch_once_t once;
    dispatch_once(&once, ^{ sys = (PBKDFFn)dlsym(RTLD_DEFAULT, "CCKeyDerivationPBKDF"); });
    if (!sys) return MeshPBKDF2SHA256Portable(pw, salt, iters);
    NSMutableData *out = [NSMutableData dataWithLength:32];
    int rc = sys(kCCPBKDF2, pw.bytes, pw.length, salt.bytes, salt.length,
                 kCCPRFHmacAlgSHA256, (uint)iters, out.mutableBytes, 32);
    return (rc == kCCSuccess) ? out : nil;
}

+ (NSData *)randomBytes:(NSUInteger)n {
    // SecRandomCopyBytes gibt es seit iOS 2.0 (arc4random_buf erst ab 4.3: fehlt auf dem touch 2G).
    // Ohne Zufall keine Schlüssel: lieber abbrechen als mit schwachen Werten weitermachen.
    NSMutableData *d = [NSMutableData dataWithLength:n];
    if (n && SecRandomCopyBytes(kSecRandomDefault, n, d.mutableBytes) != 0) abort();
    return d;
}

+ (NSData *)aes:(CCOperation)op data:(NSData *)in key:(NSData *)key iv:(NSData *)iv {
    if (key.length != kCCKeySizeAES256 || iv.length != kCCBlockSizeAES128) return nil;
    size_t bufLen = in.length + kCCBlockSizeAES128;
    NSMutableData *out = [NSMutableData dataWithLength:bufLen];
    size_t moved = 0;
    CCCryptorStatus st = CCCrypt(op, kCCAlgorithmAES, kCCOptionPKCS7Padding,
                                 key.bytes, key.length, iv.bytes,
                                 in.bytes, in.length,
                                 out.mutableBytes, bufLen, &moved);
    if (st != kCCSuccess) return nil;
    out.length = moved;
    return out;
}

+ (NSData *)aes256cbcEncrypt:(NSData *)plain key:(NSData *)key iv:(NSData *)iv {
    return [self aes:kCCEncrypt data:plain key:key iv:iv];
}

+ (NSData *)aes256cbcDecrypt:(NSData *)cipher key:(NSData *)key iv:(NSData *)iv {
    return [self aes:kCCDecrypt data:cipher key:key iv:iv];
}

@end
