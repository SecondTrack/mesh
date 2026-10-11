// NIP-44 v2 gegen die offiziellen Vektoren (nip44.vectors.json), ChaCha20 gegen RFC 8439,
// HKDF gegen RFC 5869. Dieselben Vektoren prüft die Android-App (Nip44.selfTest).
#import "MeshTest.h"
#import "MeshNip44.h"
#import "MeshKeys.h"
#import "MeshChaCha20.h"
#import "MeshCrypto.h"
#import "MeshHex.h"

static NSData *hex(NSString *s) { return [MeshHex decode:s]; }

static void testChaCha(void) {
    // RFC 8439, 2.4.2
    NSData *key = hex(@"000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f");
    NSData *nonce = hex(@"000000000000004a00000000");
    NSData *plain = [@"Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it."
                     dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *ct = [NSMutableData dataWithLength:plain.length];
    MeshChaCha20(key.bytes, nonce.bytes, 1, plain.bytes, ct.mutableBytes, plain.length);
    check([[MeshHex encode:ct] isEqualToString:
           @"6e2e359a2568f98041ba0728dd0d6981e97e7aec1d4360c20a27afccfd9fae0bf91b65c5524733ab8f593dabcd62b357"
           @"1639d624e65152ab8f530c359f0861d807ca0dbf500d6a6156a38e088a22b65e52bc514d16ccf806818ce91ab7793736"
           @"5af90bbf74a35be6b40b8eedf2785e42874d"], "ChaCha20 RFC 8439");
    NSMutableData *back = [NSMutableData dataWithLength:ct.length];
    MeshChaCha20(key.bytes, nonce.bytes, 1, ct.bytes, back.mutableBytes, ct.length);
    check([back isEqualToData:plain], "ChaCha20 zurück");
}

static void testHkdf(void) {
    // RFC 5869, Testfall 1
    NSMutableData *ikm = [NSMutableData dataWithLength:22];
    memset(ikm.mutableBytes, 0x0b, 22);
    NSData *prk = [MeshCrypto hkdfExtractSalt:hex(@"000102030405060708090a0b0c") ikm:ikm];
    check([[MeshHex encode:prk] isEqualToString:@"077709362c2e32df0ddc3f0dc47bba6390b6c73bb50f9c3122ec844ad7c2b3e5"], "HKDF-Extract");
    NSData *okm = [MeshCrypto hkdfExpand:prk info:hex(@"f0f1f2f3f4f5f6f7f8f9") length:42];
    check([[MeshHex encode:okm] isEqualToString:@"3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865"], "HKDF-Expand");
    check([MeshCrypto constantTimeEqual:okm to:[okm copy]] && ![MeshCrypto constantTimeEqual:okm to:prk], "Vergleich");
}

static void testPadding(void) {
    int cases[][2] = { {1, 32}, {16, 32}, {32, 32}, {33, 64}, {37, 64}, {45, 64}, {49, 64}, {64, 64}, {65, 96},
                       {100, 128}, {111, 128}, {200, 224}, {250, 256}, {320, 320}, {383, 384}, {384, 384},
                       {400, 448}, {500, 512}, {512, 512}, {515, 640}, {700, 768}, {800, 896}, {900, 1024},
                       {1020, 1024}, {65536, 65536} };
    BOOL all = YES;
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++)
        if ([MeshNip44 paddedLength:cases[i][0]] != (NSUInteger)cases[i][1]) { all = NO; printf("  pad %d\n", cases[i][0]); }
    check(all, "Polsterlängen");
}

static void testVectors(void) {
    NSData *ck = hex(@"c41c775356fd92eadc63ff5a0dc1da211b268cbea22316767095b2871ea1412d");
    NSData *nonce = hex(@"0000000000000000000000000000000000000000000000000000000000000001");
    NSString *expected = @"AgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABee0G5VSK0/9YypIObAtDKfYEAjD35uVkHyB0F4DwrcNaCXlCWZKaArsGrY6M9wnuTMxWfp1RTN9Xga8no+kF5Vsb";
    check([[MeshNip44 encrypt:@"a" conversationKey:ck nonce:nonce] isEqualToString:expected], "Vektor verschlüsseln");
    check([[MeshNip44 decrypt:expected conversationKey:ck] isEqualToString:@"a"], "Vektor entschlüsseln");

    // Gesprächsschlüssel aus sec1 (ich) und pub2 (Gegenüber).
    MeshKeys *k = [MeshKeys fromSeckey:hex(@"315e59ff51cb9209768cf7da80791ddcaae56ac9775eb25b6dee1234bc5d2268")];
    NSData *conv = [MeshNip44 conversationKeyWithKeys:k peerXonlyPub:hex(@"c2f9d9948dc8c7c38321e4b85c8558872eafa0641cd269db76848a6073e69133")];
    check([[MeshHex encode:conv] isEqualToString:@"3dfef0ce2a4d80a25e7a328accf73448ef67096f65f79588e358d9a0eb9013f1"], "Gesprächsschlüssel");

    // sec1 = 1, sec2 = 2 ergeben den Schlüssel des Vektors oben, von beiden Seiten.
    NSData *one = hex(@"0000000000000000000000000000000000000000000000000000000000000001");
    NSData *two = hex(@"0000000000000000000000000000000000000000000000000000000000000002");
    MeshKeys *a = [MeshKeys fromSeckey:one], *b = [MeshKeys fromSeckey:two];
    check([[MeshNip44 conversationKeyWithKeys:a peerXonlyPub:b.xonlyPub] isEqualToData:ck], "Schlüssel A→B");
    check([[MeshNip44 conversationKeyWithKeys:b peerXonlyPub:a.xonlyPub] isEqualToData:ck], "Schlüssel B→A");

    NSString *msg = @"Hallo 👋 über NIP-44";
    NSString *p = [MeshNip44 encrypt:msg keys:a peerXonlyPub:b.xonlyPub];
    check([[MeshNip44 decrypt:p keys:b peerXonlyPub:a.xonlyPub] isEqualToString:msg], "hin und zurück");
    check(![[MeshNip44 encrypt:msg keys:a peerXonlyPub:b.xonlyPub] isEqualToString:p], "zufällige Nonce");
}

static void testRejects(void) {
    NSData *ck = hex(@"c41c775356fd92eadc63ff5a0dc1da211b268cbea22316767095b2871ea1412d");
    NSString *good = [MeshNip44 encrypt:@"geheim" conversationKey:ck nonce:nil];
    // ein Zeichen im Chiffrat ändern -> MAC passt nicht
    NSMutableString *bad = [good mutableCopy];
    unichar c = [bad characterAtIndex:60];
    [bad replaceCharactersInRange:NSMakeRange(60, 1) withString:(c == 'A' ? @"B" : @"A")];
    check([MeshNip44 decrypt:bad conversationKey:ck] == nil, "veränderter Inhalt abgelehnt");
    check([MeshNip44 decrypt:[@"#" stringByAppendingString:[good substringFromIndex:1]] conversationKey:ck] == nil, "# abgelehnt");
    check([MeshNip44 decrypt:@"AgAA" conversationKey:ck] == nil, "zu kurz abgelehnt");
    NSMutableData *other = [ck mutableCopy]; ((uint8_t *)other.mutableBytes)[0] ^= 1;
    check([MeshNip44 decrypt:good conversationKey:other] == nil, "falscher Schlüssel abgelehnt");
    check([MeshNip44 encrypt:@"" conversationKey:ck nonce:nil] == nil, "leer abgelehnt");
    NSString *big = [@"" stringByPaddingToLength:65536 withString:@"x" startingAtIndex:0];
    check([MeshNip44 encrypt:big conversationKey:ck nonce:nil] == nil, "zu groß abgelehnt");
    NSString *max = [big substringFromIndex:1];
    check([[MeshNip44 decrypt:[MeshNip44 encrypt:max conversationKey:ck nonce:nil] conversationKey:ck] isEqualToString:max], "65535 Byte");
}

int main(void) {
    @autoreleasepool {
        testChaCha();
        testHkdf();
        testPadding();
        testVectors();
        testRejects();
    }
    return testsDone();
}
