#import "MeshNip44.h"
#import "MeshKeys.h"
#import "MeshCrypto.h"
#import "MeshChaCha20.h"
#import "MeshBase64.h"
#import "MeshMemory.h"

static const uint8_t kVersion = 2;
static const NSUInteger kNonce = 32, kMac = 32;
// Base64-Länge: kleinste Nachricht (32 Byte gepolstert) bis größte (65536 gepolstert), laut NIP-44.
static const NSUInteger kMinPayload = 132, kMaxPayload = 87472;

// HKDF-Expand(Gesprächsschlüssel, nonce) = ChaCha-Schlüssel ‖ ChaCha-Nonce ‖ HMAC-Schlüssel.
typedef struct { uint8_t chacha[32], nonce[12], hmac[32]; } MeshNip44MessageKeys;

static BOOL messageKeys(NSData *conversationKey, NSData *nonce, MeshNip44MessageKeys *out) {
    NSData *k = [MeshCrypto hkdfExpand:conversationKey info:nonce length:76];
    if (k.length != 76) return NO;
    memcpy(out, k.bytes, 76);
    MeshWipe(k);
    return YES;
}

static NSData *mac(const MeshNip44MessageKeys *keys, NSData *nonce, NSData *ciphertext) {
    NSMutableData *input = [nonce mutableCopy];
    [input appendData:ciphertext];
    return [MeshCrypto hmacSHA256:input key:[NSData dataWithBytes:keys->hmac length:32]];
}

@implementation MeshNip44

+ (NSUInteger)paddedLength:(NSUInteger)length {
    if (length <= 32) return 32;
    NSUInteger nextPower = 1;
    while (nextPower < length) nextPower <<= 1;   // = 1 << (floor(log2(length - 1)) + 1)
    NSUInteger chunk = nextPower <= 256 ? 32 : nextPower / 8;
    return chunk * ((length - 1) / chunk + 1);
}

+ (NSData *)conversationKeyFromSharedX:(NSData *)sharedX {
    if (sharedX.length != 32) return nil;
    return [MeshCrypto hkdfExtractSalt:[@"nip44-v2" dataUsingEncoding:NSUTF8StringEncoding] ikm:sharedX];
}

+ (NSData *)conversationKeyWithKeys:(MeshKeys *)keys peerXonlyPub:(NSData *)peer32 {
    NSData *shared = [keys ecdhSharedX:peer32];
    NSData *key = [self conversationKeyFromSharedX:shared];
    MeshWipe(shared);
    return key;
}

+ (NSString *)encrypt:(NSString *)text keys:(MeshKeys *)keys peerXonlyPub:(NSData *)peer32 {
    NSData *key = [self conversationKeyWithKeys:keys peerXonlyPub:peer32];
    NSString *payload = key ? [self encrypt:text conversationKey:key nonce:nil] : nil;
    MeshWipe(key);
    return payload;
}

+ (NSString *)decrypt:(NSString *)payload keys:(MeshKeys *)keys peerXonlyPub:(NSData *)peer32 {
    NSData *key = [self conversationKeyWithKeys:keys peerXonlyPub:peer32];
    NSString *text = key ? [self decrypt:payload conversationKey:key] : nil;
    MeshWipe(key);
    return text;
}

+ (NSString *)encrypt:(NSString *)text conversationKey:(NSData *)key nonce:(NSData *)nonce {
    NSData *plain = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (plain.length < 1 || plain.length > MeshNip44MaxPlaintext || key.length != 32) return nil;
    if (!nonce) nonce = [MeshCrypto randomBytes:kNonce];
    if (nonce.length != kNonce) return nil;

    NSUInteger padded = [self paddedLength:plain.length];
    NSMutableData *buf = [NSMutableData dataWithLength:2 + padded];
    uint8_t *b = buf.mutableBytes;
    b[0] = (uint8_t)(plain.length >> 8);
    b[1] = (uint8_t)plain.length;
    memcpy(b + 2, plain.bytes, plain.length);

    MeshNip44MessageKeys keys;
    if (!messageKeys(key, nonce, &keys)) { MeshWipe(buf); return nil; }
    NSMutableData *ct = [NSMutableData dataWithLength:buf.length];
    MeshChaCha20(keys.chacha, keys.nonce, 0, buf.bytes, ct.mutableBytes, buf.length);
    MeshWipe(buf);

    NSMutableData *out = [NSMutableData dataWithBytes:&kVersion length:1];
    [out appendData:nonce];
    [out appendData:ct];
    [out appendData:mac(&keys, nonce, ct)];
    MeshWipeBytes(&keys, sizeof(keys));
    return [MeshBase64 encode:out];
}

+ (NSString *)decrypt:(NSString *)payload conversationKey:(NSData *)key {
    if (payload.length < kMinPayload || payload.length > kMaxPayload || key.length != 32) return nil;
    if ([payload hasPrefix:@"#"]) return nil;   // laut NIP-44 für künftige, nicht base64-kodierte Versionen
    NSData *raw = [MeshBase64 decode:payload];
    if (raw.length < 1 + kNonce + 2 + 32 + kMac) return nil;
    const uint8_t *r = raw.bytes;
    if (r[0] != kVersion) return nil;

    NSData *nonce = [raw subdataWithRange:NSMakeRange(1, kNonce)];
    NSData *ct = [raw subdataWithRange:NSMakeRange(1 + kNonce, raw.length - 1 - kNonce - kMac)];
    NSData *tag = [raw subdataWithRange:NSMakeRange(raw.length - kMac, kMac)];

    MeshNip44MessageKeys keys;
    if (!messageKeys(key, nonce, &keys)) return nil;
    if (![MeshCrypto constantTimeEqual:mac(&keys, nonce, ct) to:tag]) { MeshWipeBytes(&keys, sizeof(keys)); return nil; }

    NSMutableData *buf = [NSMutableData dataWithLength:ct.length];
    MeshChaCha20(keys.chacha, keys.nonce, 0, ct.bytes, buf.mutableBytes, ct.length);
    MeshWipeBytes(&keys, sizeof(keys));

    const uint8_t *b = buf.bytes;
    NSUInteger length = ((NSUInteger)b[0] << 8) | b[1];
    NSString *text = nil;
    if (length >= 1 && buf.length == 2 + [self paddedLength:length])
        text = [[NSString alloc] initWithBytes:b + 2 length:length encoding:NSUTF8StringEncoding];
    MeshWipe(buf);
    return text;
}

@end
