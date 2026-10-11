#import "MeshSignalBundle.h"
#import "MeshSignalWire.h"
#import "MeshSignalSession.h"
#import "MeshBase64.h"

static const NSUInteger kStatic = 4 + 4 + 33 + 33 + 64, kWithOneTime = kStatic + 4 + 33;

NSString *MeshBase64URLEncode(NSData *data) {
    NSString *s = [MeshBase64 encode:data];
    s = [[s stringByReplacingOccurrencesOfString:@"+" withString:@"-"] stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    return [s stringByReplacingOccurrencesOfString:@"=" withString:@""];
}

NSData *MeshBase64URLDecode(NSString *string) {
    NSString *s = [[string stringByReplacingOccurrencesOfString:@"-" withString:@"+"] stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    while (s.length % 4) s = [s stringByAppendingString:@"="];
    return [MeshBase64 decode:s];
}

static uint32_t readU32(const uint8_t *p) { return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3]; }

static void appendU32(NSMutableData *d, uint32_t v) {
    uint8_t b[4] = { v >> 24, v >> 16, v >> 8, v };
    [d appendBytes:b length:4];
}

@implementation MeshSignalBundle

+ (instancetype)parse:(NSString *)base64url {
    NSData *raw = base64url.length ? MeshBase64URLDecode(base64url) : nil;
    if (raw.length != kStatic && raw.length != kWithOneTime) return nil;
    const uint8_t *p = raw.bytes;
    MeshSignalBundle *b = [[self alloc] init];
    b->_registrationId = readU32(p);
    b->_signedPreKeyId = readU32(p + 4);
    b->_identity = MeshSignalDeserializeKey([raw subdataWithRange:NSMakeRange(8, 33)]);
    b->_signedPreKey = MeshSignalDeserializeKey([raw subdataWithRange:NSMakeRange(41, 33)]);
    b->_signature = [raw subdataWithRange:NSMakeRange(74, 64)];
    if (raw.length == kWithOneTime) {
        b->_oneTimeId = readU32(p + kStatic);
        b->_oneTimeKey = MeshSignalDeserializeKey([raw subdataWithRange:NSMakeRange(kStatic + 4, 33)]);
        if (!b->_oneTimeKey) return nil;
    }
    return b->_identity && b->_signedPreKey ? b : nil;
}

+ (NSString *)encodeRegistrationId:(uint32_t)registrationId signedPreKeyId:(uint32_t)signedPreKeyId
                          identity:(NSData *)identity signedPreKey:(NSData *)signedPreKey signature:(NSData *)signature
                         oneTimeId:(uint32_t)oneTimeId oneTimeKey:(NSData *)oneTimeKey {
    if (identity.length != 32 || signedPreKey.length != 32 || signature.length != 64) return nil;
    NSMutableData *d = [NSMutableData data];
    appendU32(d, registrationId);
    appendU32(d, signedPreKeyId);
    [d appendData:MeshSignalSerializeKey(identity)];
    [d appendData:MeshSignalSerializeKey(signedPreKey)];
    [d appendData:signature];
    if (oneTimeKey.length == 32) {
        appendU32(d, oneTimeId);
        [d appendData:MeshSignalSerializeKey(oneTimeKey)];
    }
    return MeshBase64URLEncode(d);
}

- (BOOL)signatureValid { return MeshSignalVerify(_identity, MeshSignalSerializeKey(_signedPreKey), _signature); }

@end
