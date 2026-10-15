#import "MeshSeal.h"
#import "MeshCrypto.h"
#import "MeshMemory.h"
#import "MeshBase64.h"

static NSString *const kPrefix = @"enc2:", *const kLegacyPrefix = @"enc1:";

// Abgeleitete Schlüssel werden direkt nach Gebrauch überschrieben (MeshWipe), außer sie liegen in
// einem MeshSealKey (dann beim Sperren/Schlüsselwechsel).
static NSData *subkey(NSData *key, const char *label) {
    return [MeshCrypto hmacSHA256:[NSData dataWithBytes:label length:strlen(label)] key:key];
}

@implementation MeshSealKey {
    @package
    NSData *_enc, *_mac;   // NSMutableData aus hmacSHA256, mit MeshWipe löschbar
}

- (instancetype)initWithKey:(NSData *)key {
    if (key.length != 32) return nil;
    if ((self = [super init])) {
        _enc = subkey(key, "mesh-seal-enc");
        _mac = subkey(key, "mesh-seal-mac");
    }
    return self;
}

- (void)wipe {
    MeshWipe(_enc); MeshWipe(_mac);
    _enc = nil; _mac = nil;
}

- (void)dealloc { MeshWipe(_enc); MeshWipe(_mac); }

@end

// Vergleich in konstanter Zeit, damit der MAC nicht Byte für Byte erraten werden kann.
static BOOL equalConst(NSData *a, NSData *b) {
    if (a.length != b.length) return NO;
    const uint8_t *x = a.bytes, *y = b.bytes; uint8_t d = 0;
    for (NSUInteger i = 0; i < a.length; i++) d |= x[i] ^ y[i];
    return d == 0;
}

// MAC über Länge des Kontexts ‖ Kontext ‖ IV ‖ Chiffrat (Länge davor, damit die Grenze eindeutig ist).
static NSData *macWith(NSData *macKey, NSString *context, NSData *body) {
    NSData *c = [context ?: @"" dataUsingEncoding:NSUTF8StringEncoding];
    uint32_t n = CFSwapInt32HostToBig((uint32_t)c.length);
    NSMutableData *m = [NSMutableData dataWithBytes:&n length:4];
    [m appendData:c];
    [m appendData:body];
    return [MeshCrypto hmacSHA256:m key:macKey];
}

static NSString *openBox(NSString *sealed, NSUInteger prefixLen, NSData *encKey, NSData *(^macOf)(NSData *body)) {
    NSData *box = [MeshBase64 decode:[sealed substringFromIndex:prefixLen]];
    if (box.length < 16 + 16 + 32) return nil;
    NSData *body = [box subdataWithRange:NSMakeRange(0, box.length - 32)];
    if (!equalConst([box subdataWithRange:NSMakeRange(box.length - 32, 32)], macOf(body))) return nil;
    NSData *plain = [MeshCrypto aes256cbcDecrypt:[body subdataWithRange:NSMakeRange(16, body.length - 16)]
                                             key:encKey iv:[body subdataWithRange:NSMakeRange(0, 16)]];
    return plain ? [[NSString alloc] initWithData:plain encoding:NSUTF8StringEncoding] : nil;
}

@implementation MeshSeal

+ (BOOL)isSealed:(NSString *)value       { return [value hasPrefix:kPrefix]; }
+ (BOOL)isLegacySealed:(NSString *)value { return [value hasPrefix:kLegacyPrefix]; }

+ (NSString *)seal:(NSString *)plain sealKey:(MeshSealKey *)key context:(NSString *)context {
    if (!key) return nil;
    NSData *data = [plain dataUsingEncoding:NSUTF8StringEncoding];
    NSData *enc = key->_enc, *macKey = key->_mac;   // lokal halten: ein gleichzeitiges wipe ändert nichts mehr
    if (enc.length != 32 || macKey.length != 32 || !data) return nil;
    NSData *iv = [MeshCrypto randomBytes:16];
    NSData *ct = [MeshCrypto aes256cbcEncrypt:data key:enc iv:iv];
    if (iv.length != 16 || !ct) return nil;
    NSMutableData *box = [iv mutableCopy];
    [box appendData:ct];
    [box appendData:macWith(macKey, context, box)];
    return [kPrefix stringByAppendingString:[MeshBase64 encode:box]];
}

+ (NSString *)open:(NSString *)sealed sealKey:(MeshSealKey *)key context:(NSString *)context {
    if (!key) return nil;
    NSData *enc = key->_enc, *macKey = key->_mac;
    if (enc.length != 32 || macKey.length != 32 || ![self isSealed:sealed]) return nil;
    return openBox(sealed, kPrefix.length, enc, ^NSData *(NSData *body) { return macWith(macKey, context, body); });
}

+ (NSString *)seal:(NSString *)plain key:(NSData *)key context:(NSString *)context {
    MeshSealKey *k = [[MeshSealKey alloc] initWithKey:key];
    NSString *out = k ? [self seal:plain sealKey:k context:context] : nil;
    [k wipe];
    return out;
}

+ (NSString *)open:(NSString *)sealed key:(NSData *)key context:(NSString *)context {
    MeshSealKey *k = [[MeshSealKey alloc] initWithKey:key];
    NSString *out = k ? [self open:sealed sealKey:k context:context] : nil;
    [k wipe];
    return out;
}

+ (NSString *)openLegacy:(NSString *)sealed key:(NSData *)key {
    if (key.length != 32 || ![self isLegacySealed:sealed]) return nil;
    NSData *enc = subkey(key, "mesh-seal-enc");
    NSString *out = openBox(sealed, kLegacyPrefix.length, enc, ^NSData *(NSData *body) {
        NSData *k = subkey(key, "mesh-seal-mac");
        NSData *m = [MeshCrypto hmacSHA256:body key:k];
        MeshWipe(k);
        return m;
    });
    MeshWipe(enc);
    return out;
}

@end
