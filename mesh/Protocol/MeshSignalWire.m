#import "MeshSignalWire.h"
#import "MeshCrypto.h"

static const uint8_t kVersionByte = 0x33;   // Nachrichtenversion 3, aktuelle Version 3
static const NSUInteger kMacLength = 8;
static const uint8_t kDjbType = 0x05;

NSData *MeshSignalSerializeKey(NSData *key) {
    if (key.length != 32) return nil;
    NSMutableData *d = [NSMutableData dataWithBytes:&kDjbType length:1];
    [d appendData:key];
    return d;
}

NSData *MeshSignalDeserializeKey(NSData *key) {
    if (key.length != 33 || ((const uint8_t *)key.bytes)[0] != kDjbType) return nil;
    return [key subdataWithRange:NSMakeRange(1, 32)];
}

#pragma mark - Protobuf (nur Varints und Bytes)

static void putVarint(NSMutableData *d, uint64_t v) {
    do {
        uint8_t b = v & 0x7F;
        v >>= 7;
        if (v) b |= 0x80;
        [d appendBytes:&b length:1];
    } while (v);
}

static void putUInt(NSMutableData *d, int field, uint32_t v) { putVarint(d, (uint64_t)field << 3); putVarint(d, v); }

static void putBytes(NSMutableData *d, int field, NSData *v) {
    putVarint(d, ((uint64_t)field << 3) | 2);
    putVarint(d, v.length);
    [d appendData:v];
}

// Liest alle Felder in fields: Nummer -> NSNumber (Varint) bzw. NSData (Bytes). NO bei Fehler.
static BOOL readFields(NSData *data, NSMutableDictionary *fields) {
    const uint8_t *p = data.bytes, *end = p + data.length;
    while (p < end) {
        uint64_t key = 0; int shift = 0;
        do { if (p >= end || shift > 63) return NO; key |= (uint64_t)(*p & 0x7F) << shift; shift += 7; } while (*p++ & 0x80);
        int field = (int)(key >> 3), type = key & 7;
        uint64_t v = 0; shift = 0;
        if (type == 0 || type == 2) {
            do { if (p >= end || shift > 63) return NO; v |= (uint64_t)(*p & 0x7F) << shift; shift += 7; } while (*p++ & 0x80);
        }
        if (type == 0) fields[@(field)] = @(v);
        else if (type == 2) {
            if (v > (uint64_t)(end - p)) return NO;
            fields[@(field)] = [NSData dataWithBytes:p length:(NSUInteger)v];
            p += v;
        } else return NO;   // andere Typen kommen in diesen Nachrichten nicht vor
    }
    return YES;
}

// Feld nur, wenn es den erwarteten Typ hat (ein Angreifer kann ein Bytes-Feld als Varint schicken).
static NSData *bytesField(NSDictionary *f, int n) { return [f[@(n)] isKindOfClass:[NSData class]] ? f[@(n)] : nil; }
static NSNumber *uintField(NSDictionary *f, int n) { return [f[@(n)] isKindOfClass:[NSNumber class]] ? f[@(n)] : nil; }

static NSData *mac(NSData *macKey, NSData *sender, NSData *receiver, NSData *body) {
    NSMutableData *input = [MeshSignalSerializeKey(sender) mutableCopy];
    [input appendData:MeshSignalSerializeKey(receiver)];
    [input appendData:body];
    return [[MeshCrypto hmacSHA256:input key:macKey] subdataWithRange:NSMakeRange(0, kMacLength)];
}

@implementation MeshSignalMessage

+ (instancetype)messageWithRatchetKey:(NSData *)ratchetKey counter:(uint32_t)counter previousCounter:(uint32_t)previous
                           ciphertext:(NSData *)ciphertext macKey:(NSData *)macKey
                       senderIdentity:(NSData *)sender receiverIdentity:(NSData *)receiver {
    if (ratchetKey.length != 32 || sender.length != 32 || receiver.length != 32) return nil;
    NSMutableData *body = [NSMutableData dataWithBytes:&kVersionByte length:1];
    putBytes(body, 1, MeshSignalSerializeKey(ratchetKey));
    putUInt(body, 2, counter);
    putUInt(body, 3, previous);
    putBytes(body, 4, ciphertext);
    MeshSignalMessage *m = [[self alloc] init];
    m->_ratchetKey = [ratchetKey copy];
    m->_counter = counter;
    m->_previousCounter = previous;
    m->_ciphertext = [ciphertext copy];
    [body appendData:mac(macKey, sender, receiver, body)];
    m->_serialized = body;
    return m;
}

+ (instancetype)parse:(NSData *)serialized {
    if (serialized.length < 1 + kMacLength || ((const uint8_t *)serialized.bytes)[0] != kVersionByte) return nil;
    NSMutableDictionary *f = [NSMutableDictionary dictionary];
    if (!readFields([serialized subdataWithRange:NSMakeRange(1, serialized.length - 1 - kMacLength)], f)) return nil;
    NSData *key = MeshSignalDeserializeKey(bytesField(f, 1));
    if (!key || !uintField(f, 2) || !bytesField(f, 4)) return nil;
    MeshSignalMessage *m = [[self alloc] init];
    m->_ratchetKey = key;
    m->_counter = [uintField(f, 2) unsignedIntValue];
    m->_previousCounter = [uintField(f, 3) unsignedIntValue];
    m->_ciphertext = bytesField(f, 4);
    m->_serialized = [serialized copy];
    return m;
}

- (BOOL)verifyMacKey:(NSData *)macKey senderIdentity:(NSData *)sender receiverIdentity:(NSData *)receiver {
    NSData *body = [_serialized subdataWithRange:NSMakeRange(0, _serialized.length - kMacLength)];
    NSData *theirs = [_serialized subdataWithRange:NSMakeRange(_serialized.length - kMacLength, kMacLength)];
    NSData *ours = sender.length == 32 && receiver.length == 32 ? mac(macKey, sender, receiver, body) : nil;
    return ours && [MeshCrypto constantTimeEqual:ours to:theirs];
}

@end

@implementation MeshPreKeySignalMessage

+ (instancetype)messageWithRegistrationId:(uint32_t)registrationId preKeyId:(uint32_t)preKeyId
                           signedPreKeyId:(uint32_t)signedPreKeyId baseKey:(NSData *)baseKey
                              identityKey:(NSData *)identityKey message:(MeshSignalMessage *)message {
    if (baseKey.length != 32 || identityKey.length != 32 || !message) return nil;
    NSMutableData *d = [NSMutableData dataWithBytes:&kVersionByte length:1];
    if (preKeyId) putUInt(d, 1, preKeyId);
    putBytes(d, 2, MeshSignalSerializeKey(baseKey));
    putBytes(d, 3, MeshSignalSerializeKey(identityKey));
    putBytes(d, 4, message.serialized);
    putUInt(d, 5, registrationId);
    putUInt(d, 6, signedPreKeyId);
    MeshPreKeySignalMessage *m = [[self alloc] init];
    m->_registrationId = registrationId;
    m->_preKeyId = preKeyId;
    m->_signedPreKeyId = signedPreKeyId;
    m->_baseKey = [baseKey copy];
    m->_identityKey = [identityKey copy];
    m->_message = message;
    m->_serialized = d;
    return m;
}

+ (instancetype)parse:(NSData *)serialized {
    if (serialized.length < 2 || ((const uint8_t *)serialized.bytes)[0] != kVersionByte) return nil;
    NSMutableDictionary *f = [NSMutableDictionary dictionary];
    if (!readFields([serialized subdataWithRange:NSMakeRange(1, serialized.length - 1)], f)) return nil;
    // Wie libsignal: ohne signedPreKeyId, baseKey, identityKey oder message unvollständig.
    NSData *base = MeshSignalDeserializeKey(bytesField(f, 2)), *identity = MeshSignalDeserializeKey(bytesField(f, 3));
    MeshSignalMessage *inner = bytesField(f, 4) ? [MeshSignalMessage parse:bytesField(f, 4)] : nil;
    if (!uintField(f, 6) || !base || !identity || !inner) return nil;
    MeshPreKeySignalMessage *m = [[self alloc] init];
    m->_registrationId = [uintField(f, 5) unsignedIntValue];
    m->_preKeyId = [uintField(f, 1) unsignedIntValue];
    m->_signedPreKeyId = [uintField(f, 6) unsignedIntValue];
    m->_baseKey = base;
    m->_identityKey = identity;
    m->_message = inner;
    m->_serialized = [serialized copy];
    return m;
}

@end
