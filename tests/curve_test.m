// Curve25519: X25519 gegen RFC 7748, Ed25519-Prüfung gegen RFC 8032, Signaturen hin und zurück.
// Die Verträglichkeit mit libsignal prüft tools/dev/signal-interop.
#import "MeshTest.h"
#import "MeshCurve25519.h"
#import "MeshHex.h"

static NSData *hex(NSString *s) { return [MeshHex decode:s]; }
static NSString *hexOf(const uint8_t *b, size_t n) { return [MeshHex encode:[NSData dataWithBytes:b length:n]]; }

int main(void) { @autoreleasepool {
    uint8_t out[32];
    // RFC 7748, 5.2
    MeshX25519(out, hex(@"a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4").bytes,
               hex(@"e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c").bytes);
    check([hexOf(out, 32) isEqualToString:@"c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552"], "X25519 vector");
    // RFC 7748, 6.1
    NSData *alice = hex(@"77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a");
    NSData *bob   = hex(@"5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb");
    uint8_t ap[32], bp[32], s1[32], s2[32];
    MeshX25519Base(ap, alice.bytes);
    MeshX25519Base(bp, bob.bytes);
    check([hexOf(ap, 32) isEqualToString:@"8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a"], "alice public");
    check([hexOf(bp, 32) isEqualToString:@"de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f"], "bob public");
    MeshX25519(s1, alice.bytes, bp);
    MeshX25519(s2, bob.bytes, ap);
    check([hexOf(s1, 32) isEqualToString:@"4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742"] && !memcmp(s1, s2, 32), "shared secret");

    // RFC 8032, 7.1 Test 1 (leere Nachricht) und Test 2
    NSData *pk1 = hex(@"d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a");
    NSData *sig1 = hex(@"e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b");
    check(MeshEd25519Verify(sig1.bytes, pk1.bytes, NULL, 0), "Ed25519 test 1");
    NSData *pk2 = hex(@"3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c");
    NSData *sig2 = hex(@"92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00");
    uint8_t m2 = 0x72;
    check(MeshEd25519Verify(sig2.bytes, pk2.bytes, &m2, 1), "Ed25519 test 2");
    NSMutableData *bad = [sig2 mutableCopy]; ((uint8_t *)bad.mutableBytes)[10] ^= 1;
    check(!MeshEd25519Verify(bad.bytes, pk2.bytes, &m2, 1), "Ed25519 tampered");

    // Signatur mit dem Montgomery-Schlüssel, auch mit ungeclamptem Rohschlüssel (wie Androids Ableitung)
    int good = 0;
    for (int i = 0; i < 20; i++) {
        uint8_t priv[32], pub[32], rnd[64], sig[64], msg[33];
        arc4random_buf(priv, 32); arc4random_buf(rnd, 64); arc4random_buf(msg, 33);
        MeshX25519Base(pub, priv);
        MeshCurveSign(sig, priv, msg, sizeof(msg), rnd);
        BOOL ok = MeshCurveVerify(sig, pub, msg, sizeof(msg));
        msg[0] ^= 1;
        if (ok && !MeshCurveVerify(sig, pub, msg, sizeof(msg))) good++;
    }
    check(good == 20, "curve signatures verify, tampering detected");
    return testsDone();
}}
