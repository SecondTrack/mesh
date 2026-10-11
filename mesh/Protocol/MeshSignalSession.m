#import "MeshSignalSession.h"
#import "MeshSignalWire.h"
#import "MeshCurve25519.h"
#import "MeshCrypto.h"
#import "MeshMemory.h"

// Grenzen wie libsignal, die archivierten Zustände knapper (jeder kostet Platz in der Datenbank).
static const NSUInteger kMaxReceiverChains = 5, kMaxMessageKeys = 2000, kMaxPreviousStates = 10;
static const uint32_t kMaxSkip = 2000;   // so weit darf ein Zähler vorauslaufen

static NSData *zeros32(void) { return [NSMutableData dataWithLength:32]; }

static NSData *hkdf(NSData *ikm, NSData *salt, NSString *info, NSUInteger length) {
    NSData *prk = [MeshCrypto hkdfExtractSalt:salt ikm:ikm];
    NSData *okm = [MeshCrypto hkdfExpand:prk info:[info dataUsingEncoding:NSUTF8StringEncoding] length:length];
    MeshWipe(prk);
    return okm;
}

static NSData *chainStep(NSData *chainKey, uint8_t seed) {
    return [MeshCrypto hmacSHA256:[NSData dataWithBytes:&seed length:1] key:chainKey];
}

// cipherKey(32) ‖ macKey(32) ‖ iv(16)
static NSData *messageKeys(NSData *chainKey) {
    NSData *seed = chainStep(chainKey, 0x01);
    NSData *keys = hkdf(seed, zeros32(), @"WhisperMessageKeys", 80);
    MeshWipe(seed);
    return keys;
}

static NSData *part(NSData *d, NSUInteger offset, NSUInteger length) {
    return [NSMutableData dataWithData:[d subdataWithRange:NSMakeRange(offset, length)]];
}

#pragma mark - Schlüsselpaar

@implementation MeshSignalKeyPair

+ (instancetype)generate {
    NSMutableData *priv = [[MeshCrypto randomBytes:32] mutableCopy];
    if (priv.length != 32) return nil;
    uint8_t *k = priv.mutableBytes;
    k[0] &= 248; k[31] = (k[31] & 127) | 64;   // wie Curve25519.generatePrivateKey
    return [self withPrivateKey:priv];
}

+ (instancetype)withPrivateKey:(NSData *)privateKey {
    if (privateKey.length != 32) return nil;
    MeshSignalKeyPair *p = [[self alloc] init];
    p->_privateKey = [privateKey mutableCopy];
    NSMutableData *pub = [NSMutableData dataWithLength:32];
    MeshX25519Base(pub.mutableBytes, privateKey.bytes);
    p->_publicKey = pub;
    return p;
}

- (void)dealloc { MeshWipe(_privateKey); }

- (NSData *)agreeWith:(NSData *)publicKey {
    if (publicKey.length != 32) return nil;
    NSMutableData *out = [NSMutableData dataWithLength:32];
    MeshX25519(out.mutableBytes, _privateKey.bytes, publicKey.bytes);
    return out;
}

- (NSData *)sign:(NSData *)message {
    NSData *random = [MeshCrypto randomBytes:64];
    if (random.length != 64) return nil;
    NSMutableData *sig = [NSMutableData dataWithLength:64];
    MeshCurveSign(sig.mutableBytes, _privateKey.bytes, message.bytes, message.length, random.bytes);
    return sig;
}

@end

BOOL MeshSignalVerify(NSData *publicKey, NSData *message, NSData *signature) {
    return publicKey.length == 32 && signature.length == 64
        && MeshCurveVerify(signature.bytes, publicKey.bytes, message.bytes, message.length);
}

#pragma mark - Zustand einer Sitzung

// Empfangskette: {k: Ratchet-Schlüssel des Kontakts, c: Kettenschlüssel, i: Index, m: übersprungene
// Nachrichtenschlüssel [{i, k}]}
@interface MeshSignalState : NSObject
@property (nonatomic, copy) NSData *localIdentity, *remoteIdentity, *rootKey, *aliceBaseKey;
@property (nonatomic) uint32_t previousCounter, localRegistrationId, remoteRegistrationId;
@property (nonatomic) MeshSignalKeyPair *senderRatchet;
@property (nonatomic, copy) NSData *senderChainKey;
@property (nonatomic) uint32_t senderIndex;
@property (nonatomic) NSMutableArray *receivers;
@property (nonatomic) BOOL pending;   // noch keine Antwort: als PreKeySignalMessage senden
@property (nonatomic) uint32_t pendingPreKeyId, pendingSignedPreKeyId;
@property (nonatomic, copy) NSData *pendingBaseKey;
@end

@implementation MeshSignalState

- (instancetype)init {
    if ((self = [super init])) _receivers = [NSMutableArray array];
    return self;
}

- (NSDictionary *)plist {
    NSMutableDictionary *d = [@{ @"li": _localIdentity, @"ri": _remoteIdentity, @"rk": _rootKey,
                                 @"pc": @(_previousCounter), @"lr": @(_localRegistrationId), @"rr": @(_remoteRegistrationId),
                                 @"sp": _senderRatchet.privateKey, @"sc": _senderChainKey, @"si": @(_senderIndex),
                                 @"rc": _receivers } mutableCopy];
    if (_aliceBaseKey) d[@"ab"] = _aliceBaseKey;
    if (_pending) d[@"pk"] = @{ @"p": @(_pendingPreKeyId), @"s": @(_pendingSignedPreKeyId), @"b": _pendingBaseKey };
    return d;
}

static NSData *dataIn(NSDictionary *d, NSString *key, NSUInteger length) {
    NSData *v = d[key];
    return [v isKindOfClass:[NSData class]] && (!length || v.length == length) ? v : nil;
}

static uint32_t uintIn(NSDictionary *d, NSString *key) {
    return [d[key] isKindOfClass:[NSNumber class]] ? [d[key] unsignedIntValue] : 0;
}

+ (instancetype)fromPlist:(NSDictionary *)d {
    if (![d isKindOfClass:[NSDictionary class]]) return nil;
    MeshSignalState *s = [[self alloc] init];
    s.localIdentity = dataIn(d, @"li", 32); s.remoteIdentity = dataIn(d, @"ri", 32); s.rootKey = dataIn(d, @"rk", 32);
    s.senderRatchet = [MeshSignalKeyPair withPrivateKey:dataIn(d, @"sp", 32)];
    s.senderChainKey = dataIn(d, @"sc", 32);
    if (!s.localIdentity || !s.remoteIdentity || !s.rootKey || !s.senderRatchet || !s.senderChainKey) return nil;
    s.previousCounter = uintIn(d, @"pc"); s.senderIndex = uintIn(d, @"si");
    s.localRegistrationId = uintIn(d, @"lr"); s.remoteRegistrationId = uintIn(d, @"rr");
    s.aliceBaseKey = dataIn(d, @"ab", 32);
    for (NSDictionary *chain in [d[@"rc"] isKindOfClass:[NSArray class]] ? d[@"rc"] : @[]) {
        if (!dataIn(chain, @"k", 32) || !dataIn(chain, @"c", 32) || ![chain[@"m"] isKindOfClass:[NSArray class]]) return nil;
        NSMutableDictionary *c = [chain mutableCopy];
        c[@"m"] = [chain[@"m"] mutableCopy];
        [s.receivers addObject:c];
    }
    NSDictionary *p = d[@"pk"];
    if ([p isKindOfClass:[NSDictionary class]] && dataIn(p, @"b", 32)) {
        s.pending = YES;
        s.pendingPreKeyId = uintIn(p, @"p"); s.pendingSignedPreKeyId = uintIn(p, @"s"); s.pendingBaseKey = dataIn(p, @"b", 32);
    }
    return s;
}

- (MeshSignalState *)copyState { return [MeshSignalState fromPlist:[self plist]]; }

- (NSMutableDictionary *)receiverFor:(NSData *)ratchetKey {
    for (NSMutableDictionary *c in _receivers) if ([c[@"k"] isEqualToData:ratchetKey]) return c;
    return nil;
}

- (void)addReceiver:(NSData *)ratchetKey chainKey:(NSData *)chainKey {
    [_receivers addObject:[@{ @"k": ratchetKey, @"c": chainKey, @"i": @0, @"m": [NSMutableArray array] } mutableCopy]];
    while (_receivers.count > kMaxReceiverChains) [_receivers removeObjectAtIndex:0];
}

// RootKey.createChain: neuer Root- und Kettenschlüssel aus einem DH-Schritt.
- (NSData *)ratchetRootWith:(NSData *)theirRatchet ours:(MeshSignalKeyPair *)ours {
    NSData *shared = [ours agreeWith:theirRatchet];
    NSData *derived = hkdf(shared, _rootKey, @"WhisperRatchet", 64);
    MeshWipe(shared);
    self.rootKey = part(derived, 0, 32);
    NSData *chain = part(derived, 32, 32);
    MeshWipe(derived);
    return chain;
}

- (NSData *)encrypt:(NSData *)plaintext isPreKey:(BOOL *)isPreKey {
    NSData *keys = messageKeys(_senderChainKey);
    NSData *ct = [MeshCrypto aes256cbcEncrypt:plaintext key:part(keys, 0, 32) iv:part(keys, 64, 16)];
    MeshSignalMessage *m = ct ? [MeshSignalMessage messageWithRatchetKey:_senderRatchet.publicKey counter:_senderIndex
                                                         previousCounter:_previousCounter ciphertext:ct macKey:part(keys, 32, 32)
                                                          senderIdentity:_localIdentity receiverIdentity:_remoteIdentity] : nil;
    MeshWipe(keys);
    if (!m) return nil;
    NSData *next = chainStep(_senderChainKey, 0x02);
    self.senderChainKey = next;
    MeshWipe(next);
    _senderIndex++;
    if (isPreKey) *isPreKey = _pending;
    if (!_pending) return m.serialized;
    return [MeshPreKeySignalMessage messageWithRegistrationId:_localRegistrationId preKeyId:_pendingPreKeyId
                                               signedPreKeyId:_pendingSignedPreKeyId baseKey:_pendingBaseKey
                                                  identityKey:_localIdentity message:m].serialized;
}

// SessionCipher.decrypt(SessionState, SignalMessage). Verändert den Zustand: nur auf einer Kopie aufrufen.
- (NSData *)decrypt:(MeshSignalMessage *)m error:(MeshSignalDecryptError *)error {
    *error = MeshSignalDecryptInvalid;
    NSMutableDictionary *chain = [self receiverFor:m.ratchetKey];
    if (!chain) {   // neuer Ratchet-Schlüssel des Kontakts: DH-Schritt in beide Richtungen
        NSData *receive = [self ratchetRootWith:m.ratchetKey ours:_senderRatchet];
        MeshSignalKeyPair *fresh = [MeshSignalKeyPair generate];
        NSData *send = [self ratchetRootWith:m.ratchetKey ours:fresh];
        [self addReceiver:m.ratchetKey chainKey:receive];
        _previousCounter = _senderIndex > 0 ? _senderIndex - 1 : 0;
        self.senderRatchet = fresh;
        self.senderChainKey = send;
        _senderIndex = 0;
        chain = [self receiverFor:m.ratchetKey];
    }

    NSData *keys = nil;
    uint32_t index = [chain[@"i"] unsignedIntValue];
    NSMutableArray *skipped = chain[@"m"];
    if (index > m.counter) {
        for (NSUInteger i = 0; i < skipped.count && !keys; i++)
            if ([skipped[i][@"i"] unsignedIntValue] == m.counter) { keys = skipped[i][@"k"]; [skipped removeObjectAtIndex:i]; }
        if (!keys) { *error = MeshSignalDecryptDuplicate; return nil; }
    } else {
        if (m.counter - index > kMaxSkip) return nil;
        NSData *ck = chain[@"c"];
        for (; index < m.counter; index++) {
            [skipped addObject:@{ @"i": @(index), @"k": messageKeys(ck) }];
            ck = chainStep(ck, 0x02);
        }
        while (skipped.count > kMaxMessageKeys) [skipped removeObjectAtIndex:0];
        keys = messageKeys(ck);
        chain[@"c"] = chainStep(ck, 0x02);
        chain[@"i"] = @(index + 1);
    }

    if (![m verifyMacKey:part(keys, 32, 32) senderIdentity:_remoteIdentity receiverIdentity:_localIdentity]) return nil;
    NSData *plain = [MeshCrypto aes256cbcDecrypt:m.ciphertext key:part(keys, 0, 32) iv:part(keys, 64, 16)];
    if (!plain) return nil;
    _pending = NO;   // der Kontakt hat die Sitzung, ab jetzt normale Nachrichten
    *error = MeshSignalDecryptOK;
    return plain;
}

@end

#pragma mark - Sitzung (aktueller und archivierte Zustände)

@implementation MeshSignalSession {
    MeshSignalState *_state;
    NSMutableArray *_previous;   // MeshSignalState, neueste zuerst
}

- (instancetype)initWithState:(MeshSignalState *)state {
    if ((self = [super init])) { _state = state; _previous = [NSMutableArray array]; }
    return self;
}

- (NSData *)remoteIdentity { return _state.remoteIdentity; }

static NSMutableData *x3dhSecret(void) {
    NSMutableData *s = [NSMutableData dataWithLength:32];
    memset(s.mutableBytes, 0xFF, 32);
    return s;
}

static void appendWiped(NSMutableData *secret, NSData *dh) { [secret appendData:dh]; MeshWipe(dh); }

+ (instancetype)sessionWithOurIdentity:(MeshSignalKeyPair *)identity registrationId:(uint32_t)registrationId
                         theirIdentity:(NSData *)theirIdentity registrationId:(uint32_t)theirRegistrationId
                          signedPreKey:(NSData *)signedPreKey signedPreKeyId:(uint32_t)signedPreKeyId
                            oneTimeKey:(NSData *)oneTime oneTimeKeyId:(uint32_t)oneTimeId {
    if (theirIdentity.length != 32 || signedPreKey.length != 32 || (oneTime && oneTime.length != 32)) return nil;
    MeshSignalKeyPair *base = [MeshSignalKeyPair generate];
    NSMutableData *secret = x3dhSecret();
    appendWiped(secret, [identity agreeWith:signedPreKey]);
    appendWiped(secret, [base agreeWith:theirIdentity]);
    appendWiped(secret, [base agreeWith:signedPreKey]);
    if (oneTime) appendWiped(secret, [base agreeWith:oneTime]);
    NSData *derived = hkdf(secret, zeros32(), @"WhisperText", 64);
    MeshWipe(secret);

    MeshSignalState *s = [[MeshSignalState alloc] init];
    s.localIdentity = identity.publicKey;
    s.remoteIdentity = theirIdentity;
    s.rootKey = part(derived, 0, 32);
    [s addReceiver:signedPreKey chainKey:part(derived, 32, 32)];
    MeshWipe(derived);
    MeshSignalKeyPair *sending = [MeshSignalKeyPair generate];
    s.senderChainKey = [s ratchetRootWith:signedPreKey ours:sending];
    s.senderRatchet = sending;
    s.localRegistrationId = registrationId;
    s.remoteRegistrationId = theirRegistrationId;
    s.aliceBaseKey = base.publicKey;
    s.pending = YES;
    s.pendingPreKeyId = oneTime ? oneTimeId : 0;
    s.pendingSignedPreKeyId = signedPreKeyId;
    s.pendingBaseKey = base.publicKey;
    return s.senderChainKey && s.rootKey ? [[self alloc] initWithState:s] : nil;
}

+ (MeshSignalState *)bobStateFor:(MeshPreKeySignalMessage *)message ourIdentity:(MeshSignalKeyPair *)identity
                  registrationId:(uint32_t)registrationId signedPreKey:(MeshSignalKeyPair *)signedPreKey
                      oneTimeKey:(MeshSignalKeyPair *)oneTime {
    NSMutableData *secret = x3dhSecret();
    appendWiped(secret, [signedPreKey agreeWith:message.identityKey]);
    appendWiped(secret, [identity agreeWith:message.baseKey]);
    appendWiped(secret, [signedPreKey agreeWith:message.baseKey]);
    if (oneTime) appendWiped(secret, [oneTime agreeWith:message.baseKey]);
    NSData *derived = hkdf(secret, zeros32(), @"WhisperText", 64);
    MeshWipe(secret);

    MeshSignalState *s = [[MeshSignalState alloc] init];
    s.localIdentity = identity.publicKey;
    s.remoteIdentity = message.identityKey;
    s.rootKey = part(derived, 0, 32);
    s.senderRatchet = signedPreKey;
    s.senderChainKey = part(derived, 32, 32);
    MeshWipe(derived);
    s.localRegistrationId = registrationId;
    s.remoteRegistrationId = message.registrationId;
    s.aliceBaseKey = message.baseKey;
    return s;
}

+ (instancetype)sessionFromPreKeyMessage:(MeshPreKeySignalMessage *)message ourIdentity:(MeshSignalKeyPair *)identity
                          registrationId:(uint32_t)registrationId signedPreKey:(MeshSignalKeyPair *)signedPreKey
                              oneTimeKey:(MeshSignalKeyPair *)oneTime {
    return [[self alloc] initWithState:[self bobStateFor:message ourIdentity:identity registrationId:registrationId
                                            signedPreKey:signedPreKey oneTimeKey:oneTime]];
}

- (BOOL)hasBaseKey:(NSData *)baseKey {
    if ([_state.aliceBaseKey isEqualToData:baseKey]) return YES;
    for (MeshSignalState *s in _previous) if ([s.aliceBaseKey isEqualToData:baseKey]) return YES;
    return NO;
}

- (void)archive:(MeshSignalState *)state {
    [_previous insertObject:state atIndex:0];
    while (_previous.count > kMaxPreviousStates) [_previous removeLastObject];
}

- (void)acceptPreKeyMessage:(MeshPreKeySignalMessage *)message ourIdentity:(MeshSignalKeyPair *)identity
             registrationId:(uint32_t)registrationId signedPreKey:(MeshSignalKeyPair *)signedPreKey
                 oneTimeKey:(MeshSignalKeyPair *)oneTime {
    [self archive:_state];
    _state = [MeshSignalSession bobStateFor:message ourIdentity:identity registrationId:registrationId
                               signedPreKey:signedPreKey oneTimeKey:oneTime];
}

- (NSData *)encrypt:(NSData *)plaintext isPreKey:(BOOL *)isPreKey { return [_state encrypt:plaintext isPreKey:isPreKey]; }

// Erst der aktuelle Zustand, dann die archivierten (z.B. Nachrichten, die vor einem Neuaufbau
// unterwegs waren). Jeder Versuch auf einer Kopie; der erfolgreiche wird zum aktuellen.
- (NSData *)decrypt:(MeshSignalMessage *)message error:(MeshSignalDecryptError *)error {
    MeshSignalState *attempt = [_state copyState];
    NSData *plain = [attempt decrypt:message error:error];
    if (plain) { _state = attempt; return plain; }
    if (*error == MeshSignalDecryptDuplicate) return nil;
    for (NSUInteger i = 0; i < _previous.count; i++) {
        attempt = [_previous[i] copyState];
        plain = [attempt decrypt:message error:error];
        if (*error == MeshSignalDecryptDuplicate) return nil;
        if (!plain) continue;
        [_previous removeObjectAtIndex:i];
        [self archive:_state];
        _state = attempt;
        return plain;
    }
    *error = MeshSignalDecryptInvalid;
    return nil;
}

#pragma mark - Speichern

- (NSData *)propertyList {
    NSMutableArray *previous = [NSMutableArray array];
    for (MeshSignalState *s in _previous) [previous addObject:[s plist]];
    return [NSPropertyListSerialization dataWithPropertyList:@{ @"v": @1, @"s": [_state plist], @"p": previous }
                                                      format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
}

+ (instancetype)fromPropertyList:(NSData *)plist {
    NSDictionary *d = plist ? [NSPropertyListSerialization propertyListWithData:plist options:NSPropertyListImmutable format:NULL error:NULL] : nil;
    if (![d isKindOfClass:[NSDictionary class]]) return nil;
    MeshSignalState *current = [MeshSignalState fromPlist:d[@"s"]];
    if (!current) return nil;
    MeshSignalSession *session = [[self alloc] initWithState:current];
    for (NSDictionary *p in [d[@"p"] isKindOfClass:[NSArray class]] ? d[@"p"] : @[]) {
        MeshSignalState *s = [MeshSignalState fromPlist:p];
        if (s) [session->_previous addObject:s];
    }
    return session;
}

@end
