#import "MeshSignal.h"
#import "MeshSignalSession.h"
#import "MeshSignalWire.h"
#import "MeshSignalBundle.h"
#import "MeshCrypto.h"
#import "MeshHex.h"
#import "MeshBase64.h"
#import "MeshMemory.h"
#import "MeshLog.h"

NSString *const MeshSignalScheme = @"sg1:";

static const uint32_t kSignedPreKeyId = 1;
static const NSUInteger kOneTimePool = 720;   // wie Android: ~2 h Live-QR mit 10-s-Takt

// Schlüssel im Speicher
static NSString *const kSignedPreKey = @"spk";       // Property-List {k: privat, s: Signatur}
static NSString *const kOneTimeOrder = @"pk-order";  // IDs der Einmal-PreKeys, älteste zuerst (je 4 Byte)
static NSString *oneTimeKey(uint32_t keyId) { return [NSString stringWithFormat:@"pk.%u", keyId]; }
static NSString *sessionKey(NSString *peer) { return [@"s." stringByAppendingString:peer]; }
static NSString *identityKey(NSString *peer) { return [@"id." stringByAppendingString:peer]; }

static NSData *sha256(NSString *label, NSData *seed) {
    NSMutableData *in = [[label dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [in appendData:seed];
    NSData *out = [MeshCrypto sha256:in];
    MeshWipe(in);
    return out;
}

@implementation MeshSignal {
    id<MeshSignalStorage> _storage;
    MeshSignalKeyPair *_identity;
    uint32_t _registrationId;
    MeshSignalKeyPair *_signedPreKey;
    NSData *_signature;
}

- (instancetype)initWithStorage:(id<MeshSignalStorage>)storage seed:(NSData *)nsec {
    if (nsec.length != 32 || !(self = [super init])) return nil;
    _storage = storage;
    NSData *scalar = sha256(@"mesh:signal:id:v1", nsec);
    _identity = [MeshSignalKeyPair withPrivateKey:scalar];
    MeshWipe(scalar);
    NSData *reg = sha256(@"mesh:signal:reg:v1", nsec);
    const uint8_t *r = reg.bytes;
    _registrationId = ((((uint32_t)r[0] << 8) | r[1]) & 0x3FFF) % 16380 + 1;
    [self loadSignedPreKey];
    return _signedPreKey ? self : nil;
}

- (NSData *)identityKey { return _identity.publicKey; }

// Signierter PreKey: geladen, oder neu, wenn keiner da ist oder er nicht (mehr) zur Identität passt.
- (void)loadSignedPreKey {
    NSData *stored = [_storage signalValueForKey:kSignedPreKey];
    NSDictionary *d = stored ? [NSPropertyListSerialization propertyListWithData:stored options:0 format:NULL error:NULL] : nil;
    MeshSignalKeyPair *pair = [d isKindOfClass:[NSDictionary class]] ? [MeshSignalKeyPair withPrivateKey:d[@"k"]] : nil;
    NSData *sig = [d isKindOfClass:[NSDictionary class]] ? d[@"s"] : nil;
    if (pair && MeshSignalVerify(_identity.publicKey, MeshSignalSerializeKey(pair.publicKey), sig)) {
        _signedPreKey = pair; _signature = sig;
        return;
    }
    pair = [MeshSignalKeyPair generate];
    sig = [_identity sign:MeshSignalSerializeKey(pair.publicKey)];
    if (!pair || !sig) return;
    NSData *plist = [NSPropertyListSerialization dataWithPropertyList:@{ @"k": pair.privateKey, @"s": sig }
                                                               format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
    [_storage setSignalValue:plist forKey:kSignedPreKey];
    _signedPreKey = pair; _signature = sig;
}

#pragma mark - Bundles

- (NSString *)bundle {
    return [MeshSignalBundle encodeRegistrationId:_registrationId signedPreKeyId:kSignedPreKeyId identity:_identity.publicKey
                                     signedPreKey:_signedPreKey.publicKey signature:_signature oneTimeId:0 oneTimeKey:nil];
}

- (NSString *)bundleWithFreshOneTimeKey {
    MeshSignalKeyPair *pair = [MeshSignalKeyPair generate];
    uint32_t keyId = 0;
    for (int tries = 0; tries < 8 && (!keyId || [_storage signalValueForKey:oneTimeKey(keyId)]); tries++)
        keyId = 1 + arc4random_uniform(0xFFFFFE);
    if (!pair || !keyId) return [self bundle];
    [_storage setSignalValue:pair.privateKey forKey:oneTimeKey(keyId)];

    // Nur die jüngsten bleiben gültig, sonst wächst die Datenbank mit jedem angezeigten QR-Code.
    NSMutableData *order = [[_storage signalValueForKey:kOneTimeOrder] mutableCopy] ?: [NSMutableData data];
    uint32_t be = CFSwapInt32HostToBig(keyId);
    [order appendBytes:&be length:4];
    while (order.length / 4 > kOneTimePool) {
        uint32_t oldest = CFSwapInt32BigToHost(*(const uint32_t *)order.bytes);
        [_storage setSignalValue:nil forKey:oneTimeKey(oldest)];
        [order replaceBytesInRange:NSMakeRange(0, 4) withBytes:NULL length:0];
    }
    [_storage setSignalValue:order forKey:kOneTimeOrder];
    return [MeshSignalBundle encodeRegistrationId:_registrationId signedPreKeyId:kSignedPreKeyId identity:_identity.publicKey
                                     signedPreKey:_signedPreKey.publicKey signature:_signature oneTimeId:keyId oneTimeKey:pair.publicKey];
}

#pragma mark - Sitzungen

- (MeshSignalSession *)sessionWith:(NSString *)peer {
    return [MeshSignalSession fromPropertyList:[_storage signalValueForKey:sessionKey(peer)]];
}

- (BOOL)store:(MeshSignalSession *)session for:(NSString *)peer {
    return [_storage setSignalValue:[session propertyList] forKey:sessionKey(peer)];
}

- (BOOL)hasSessionWith:(NSString *)peer { return [self sessionWith:peer] != nil; }

- (void)forgetPeer:(NSString *)peer {
    [_storage setSignalValue:nil forKey:sessionKey(peer)];
    [_storage setSignalValue:nil forKey:identityKey(peer)];
}

// Vertrauen wie MeshSignalStore.isTrustedIdentity: neu oder gleich, sonst nur bei Unverifizierten.
- (BOOL)trust:(NSData *)identity of:(NSString *)peer verified:(BOOL)verified {
    NSData *known = [_storage signalValueForKey:identityKey(peer)];
    return !known || [known isEqualToData:identity] || !verified;
}

- (NSString *)encrypt:(NSString *)plaintext to:(NSString *)peer bundle:(NSString *)peerBundle
             verified:(BOOL)verified refused:(BOOL *)refused {
    if (refused) *refused = NO;
    MeshSignalSession *session = [self sessionWith:peer];
    MeshSignalBundle *bundle = peerBundle.length ? [MeshSignalBundle parse:peerBundle] : nil;
    if (bundle && ![bundle signatureValid]) bundle = nil;
    // Gehört das Bundle zu einer anderen Identität als die bekannte: bei verifizierten Kontakten
    // ablehnen, sonst die alte Sitzung verwerfen und neu aufbauen.
    if (bundle && ![self trust:bundle.identity of:peer verified:verified]) { if (refused) *refused = YES; return nil; }
    if (session && bundle && ![session.remoteIdentity isEqualToData:bundle.identity]) session = nil;
    if (!session) {
        if (!bundle) return nil;
        session = [MeshSignalSession sessionWithOurIdentity:_identity registrationId:_registrationId
                                              theirIdentity:bundle.identity registrationId:bundle.registrationId
                                               signedPreKey:bundle.signedPreKey signedPreKeyId:bundle.signedPreKeyId
                                                 oneTimeKey:bundle.oneTimeKey oneTimeKeyId:bundle.oneTimeId];
        if (!session) return nil;
        [_storage setSignalValue:bundle.identity forKey:identityKey(peer)];
    }
    BOOL preKey = NO;
    NSData *wire = [session encrypt:[plaintext dataUsingEncoding:NSUTF8StringEncoding] isPreKey:&preKey];
    // Ungespeichert würde die nächste Nachricht denselben Kettenschlüssel (AES-Schlüssel und IV) nutzen.
    if (!wire || ![self store:session for:peer]) return nil;
    return [NSString stringWithFormat:@"%@%@:%@", MeshSignalScheme, preKey ? @"p" : @"m", [MeshBase64 encode:wire]];
}

- (NSString *)decrypt:(NSString *)content from:(NSString *)peer verified:(BOOL)verified {
    if (![content hasPrefix:MeshSignalScheme] || content.length < MeshSignalScheme.length + 3) return nil;
    NSString *type = [content substringWithRange:NSMakeRange(MeshSignalScheme.length, 2)];
    NSData *wire = [MeshBase64 decode:[content substringFromIndex:MeshSignalScheme.length + 2]];
    MeshSignalSession *session = [self sessionWith:peer];
    MeshSignalMessage *message = nil;
    uint32_t usedOneTime = 0;

    if ([type isEqualToString:@"p:"]) {
        MeshPreKeySignalMessage *pre = [MeshPreKeySignalMessage parse:wire];
        if (!pre || ![self trust:pre.identityKey of:peer verified:verified]) return nil;
        message = pre.message;
        if (!session || ![session hasBaseKey:pre.baseKey]) {
            if (pre.signedPreKeyId != kSignedPreKeyId) return nil;
            MeshSignalKeyPair *oneTime = nil;
            if (pre.preKeyId) {
                oneTime = [MeshSignalKeyPair withPrivateKey:[_storage signalValueForKey:oneTimeKey(pre.preKeyId)]];
                if (!oneTime) return nil;   // schon eingelöst oder verfallen
                usedOneTime = pre.preKeyId;
            }
            if (session) [session acceptPreKeyMessage:pre ourIdentity:_identity registrationId:_registrationId
                                         signedPreKey:_signedPreKey oneTimeKey:oneTime];
            else session = [MeshSignalSession sessionFromPreKeyMessage:pre ourIdentity:_identity registrationId:_registrationId
                                                          signedPreKey:_signedPreKey oneTimeKey:oneTime];
        }
    } else if ([type isEqualToString:@"m:"]) {
        message = [MeshSignalMessage parse:wire];
    }
    if (!message || !session) return nil;

    MeshSignalDecryptError error;
    NSData *plain = [session decrypt:message error:&error];
    if (!plain) { MeshLog(@"Signal: %@", error == MeshSignalDecryptDuplicate ? @"schon gelesen" : @"passt zu keiner Sitzung"); return nil; }
    [self store:session for:peer];
    [_storage setSignalValue:session.remoteIdentity forKey:identityKey(peer)];
    if (usedOneTime) [_storage setSignalValue:nil forKey:oneTimeKey(usedOneTime)];
    return [[NSString alloc] initWithData:plain encoding:NSUTF8StringEncoding];
}

#pragma mark - Identitäten vergleichen

+ (BOOL)bundle:(NSString *)a sameIdentityAs:(NSString *)b {
    NSData *ia = [MeshSignalBundle parse:a].identity, *ib = [MeshSignalBundle parse:b].identity;
    return ia && [ia isEqualToData:ib];
}

static NSData *sha512(NSData *a, NSData *b) {
    NSMutableData *in = [a mutableCopy];
    [in appendData:b];
    return [MeshCrypto sha512:in];
}

- (NSArray *)safetyNumberWith:(NSString *)peer myPubkey:(NSString *)myPubkey peerBundle:(NSString *)peerBundle {
    NSData *theirs = [MeshSignalBundle parse:peerBundle].identity;
    NSData *me = [MeshHex decode:myPubkey], *them = [MeshHex decode:peer];
    if (!theirs || me.length != 32 || them.length != 32) return nil;
    NSData *a = sha512(MeshSignalSerializeKey(_identity.publicKey), me);
    NSData *b = sha512(MeshSignalSerializeKey(theirs), them);
    // Sortiert, damit beide Seiten dasselbe sehen.
    BOOL aFirst = memcmp(a.bytes, b.bytes, 64) <= 0;
    NSData *digest = sha512(aFirst ? a : b, aFirst ? b : a);
    const uint8_t *h = digest.bytes;
    NSMutableArray *groups = [NSMutableArray array];
    for (int i = 0; i < 12; i++) {
        uint64_t v = 0;
        for (int j = 0; j < 5; j++) v = (v << 8) | h[i * 5 + j];
        [groups addObject:[NSString stringWithFormat:@"%05llu", v % 100000]];
    }
    return groups;
}

@end
