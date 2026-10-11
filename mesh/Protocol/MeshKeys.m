#import "MeshKeys.h"
#import "MeshCrypto.h"
#import "MeshMemory.h"

#include "secp256k1.h"
#include "secp256k1_schnorrsig.h"
#include "secp256k1_extrakeys.h"
#include "secp256k1_ecdh.h"

// Ein prozessweiter, randomisierter Kontext (Signieren + Verifizieren).
static secp256k1_context *ctx(void) {
    static secp256k1_context *c = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        c = secp256k1_context_create(SECP256K1_CONTEXT_SIGN | SECP256K1_CONTEXT_VERIFY);
        NSData *r = [MeshCrypto randomBytes:32];
        if (r) (void)secp256k1_context_randomize(c, r.bytes);
    });
    return c;
}

// NIP-04-ECDH: die rohe X-Koordinate als Shared Secret (nicht sha256(punkt)).
static int ecdh_xonly(unsigned char *out, const unsigned char *x32,
                      const unsigned char *y32, void *data) {
    (void)y32; (void)data;
    memcpy(out, x32, 32);
    return 1;
}

@implementation MeshKeys {
    unsigned char _sk[32];
    unsigned char _xpub[32];
    BOOL _wiped;
}

- (void)dealloc { MeshWipeBytes(_sk, sizeof(_sk)); }
- (void)wipe    { MeshWipeBytes(_sk, sizeof(_sk)); _wiped = YES; }

- (NSData *)seckey   { return _wiped ? nil : [NSMutableData dataWithBytes:_sk length:32]; }   // Kopie, mit MeshWipe löschbar
- (NSData *)xonlyPub { return [NSData dataWithBytes:_xpub length:32]; }

+ (instancetype)generate {
    for (int tries = 0; tries < 8; tries++) {
        NSData *sk = [MeshCrypto randomBytes:32];
        MeshKeys *k = [self fromSeckey:sk];
        if (k) return k;   // extrem selten ungültig -> neu würfeln
    }
    return nil;
}

+ (instancetype)fromSeckey:(NSData *)sk {
    if (sk.length != 32) return nil;
    if (!secp256k1_ec_seckey_verify(ctx(), sk.bytes)) return nil;

    secp256k1_keypair kp;
    if (!secp256k1_keypair_create(ctx(), &kp, sk.bytes)) return nil;

    secp256k1_xonly_pubkey xpub;
    int ok = secp256k1_keypair_xonly_pub(ctx(), &xpub, NULL, &kp);
    MeshWipeBytes(&kp, sizeof(kp));
    if (!ok) return nil;

    MeshKeys *k = [[self alloc] init];
    memcpy(k->_sk, sk.bytes, 32);
    secp256k1_xonly_pubkey_serialize(ctx(), k->_xpub, &xpub);
    return k;
}

- (NSData *)schnorrSign:(NSData *)msg32 {
    if (msg32.length != 32 || _wiped) return nil;
    secp256k1_keypair kp;
    if (!secp256k1_keypair_create(ctx(), &kp, _sk)) return nil;

    unsigned char sig[64];
    NSData *aux = [MeshCrypto randomBytes:32];   // BIP-340 aux_rand
    int ok = secp256k1_schnorrsig_sign32(ctx(), sig, msg32.bytes, &kp, aux.bytes);
    MeshWipeBytes(&kp, sizeof(kp));
    return ok ? [NSData dataWithBytes:sig length:64] : nil;
}

+ (BOOL)schnorrVerify:(NSData *)sig64 msg32:(NSData *)msg32 xonlyPub:(NSData *)pub32 {
    if (sig64.length != 64 || msg32.length != 32 || pub32.length != 32) return NO;
    secp256k1_xonly_pubkey xpub;
    if (!secp256k1_xonly_pubkey_parse(ctx(), &xpub, pub32.bytes)) return NO;
    return secp256k1_schnorrsig_verify(ctx(), sig64.bytes, msg32.bytes, 32, &xpub) == 1;
}

- (NSData *)derivedKey:(NSString *)label {
    if (_wiped) return nil;
    NSData *sk = [NSData dataWithBytesNoCopy:_sk length:32 freeWhenDone:NO];
    return [MeshCrypto hmacSHA256:[label dataUsingEncoding:NSUTF8StringEncoding] key:sk];
}

- (NSData *)ecdhSharedX:(NSData *)peerXonlyPub32 {
    if (peerXonlyPub32.length != 32 || _wiped) return nil;
    // x-only -> vollen Pubkey mit angenommenem geraden Y (0x02-Prefix, NIP-04-Konvention).
    unsigned char comp[33];
    comp[0] = 0x02;
    memcpy(comp + 1, peerXonlyPub32.bytes, 32);
    secp256k1_pubkey pub;
    if (!secp256k1_ec_pubkey_parse(ctx(), &pub, comp, 33)) return nil;

    unsigned char out[32];
    int ok = secp256k1_ecdh(ctx(), out, &pub, _sk, ecdh_xonly, NULL);
    NSData *shared = ok ? [NSMutableData dataWithBytes:out length:32] : nil;   // mit MeshWipe löschbar
    MeshWipeBytes(out, sizeof(out));
    return shared;
}

@end
