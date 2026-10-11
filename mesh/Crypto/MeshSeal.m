#import "MeshSeal.h"
#import "MeshCrypto.h"
#import "MeshMemory.h"
#import "MeshBase64.h"

static NSString *const kPrefix = @"enc2:", *const kLegacyPrefix = @"enc1:";

// Abgeleitete Schlüssel werden direkt nach Gebrauch überschrieben (MeshWipe).
static NSData *subkey(NSData *key, const char *label) {
    return [MeshCrypto hmacSHA256:[NSData dataWithBytes:label length:strlen(label)] key:key];
}

// Vergleich in konstanter Zeit, damit der MAC nicht Byte für Byte erraten werden kann.
static BOOL equalConst(NSData *a, NSData *b) {
    if (a.length != b.length) return NO;
    const uint8_t *x = a.bytes, *y = b.bytes; uint8_t d = 0;
    for (NSUInteger i = 0; i < a.length; i++) d |= x[i] ^ y[i];
    return d == 0;
}

// MAC über Länge des Kontexts ‖ Kontext ‖ IV ‖ Chiffrat (Länge davor, damit die Grenze eindeutig ist).
static NSData *mac(NSData *key, NSString *context, NSData *body) {
    NSData *c = [context ?: @"" dataUsingEncoding:NSUTF8StringEncoding];
    uint32_t n = CFSwapInt32HostToBig((uint32_t)c.length);
    NSMutableData *m = [NSMutableData dataWithBytes:&n length:4];
    [m appendData:c];
    [m appendData:body];
    NSData *k = subkey(key, "mesh-seal-mac");
    NSData *out = [MeshCrypto hmacSHA256:m key:k];
    MeshWipe(k);
    return out;
}

static NSString *openBox(NSString *sealed, NSUInteger prefixLen, NSData *key, NSData *(^macOf)(NSData *body)) {
    NSData *box = [MeshBase64 decode:[sealed substringFromIndex:prefixLen]];
    if (box.length < 16 + 16 + 32) return nil;
    NSData *body = [box subdataWithRange:NSMakeRange(0, box.length - 32)];
    if (!equalConst([box subdataWithRange:NSMakeRange(box.length - 32, 32)], macOf(body))) return nil;
    NSData *k = subkey(key, "mesh-seal-enc");
    NSData *plain = [MeshCrypto aes256cbcDecrypt:[body subdataWithRange:NSMakeRange(16, body.length - 16)]
                                             key:k iv:[body subdataWithRange:NSMakeRange(0, 16)]];
    MeshWipe(k);
    return plain ? [[NSString alloc] initWithData:plain encoding:NSUTF8StringEncoding] : nil;
}

@implementation MeshSeal

+ (BOOL)isSealed:(NSString *)value       { return [value hasPrefix:kPrefix]; }
+ (BOOL)isLegacySealed:(NSString *)value { return [value hasPrefix:kLegacyPrefix]; }

+ (NSString *)seal:(NSString *)plain key:(NSData *)key context:(NSString *)context {
    NSData *data = [plain dataUsingEncoding:NSUTF8StringEncoding];
    if (key.length != 32 || !data) return nil;
    NSData *iv = [MeshCrypto randomBytes:16];
    NSData *k = subkey(key, "mesh-seal-enc");
    NSData *ct = [MeshCrypto aes256cbcEncrypt:data key:k iv:iv];
    MeshWipe(k);
    if (iv.length != 16 || !ct) return nil;
    NSMutableData *box = [iv mutableCopy];
    [box appendData:ct];
    [box appendData:mac(key, context, box)];
    return [kPrefix stringByAppendingString:[MeshBase64 encode:box]];
}

+ (NSString *)open:(NSString *)sealed key:(NSData *)key context:(NSString *)context {
    if (key.length != 32 || ![self isSealed:sealed]) return nil;
    return openBox(sealed, kPrefix.length, key, ^NSData *(NSData *body) { return mac(key, context, body); });
}

+ (NSString *)openLegacy:(NSString *)sealed key:(NSData *)key {
    if (key.length != 32 || ![self isLegacySealed:sealed]) return nil;
    return openBox(sealed, kLegacyPrefix.length, key, ^NSData *(NSData *body) {
        NSData *k = subkey(key, "mesh-seal-mac");
        NSData *out = [MeshCrypto hmacSHA256:body key:k];
        MeshWipe(k);
        return out;
    });
}

@end
