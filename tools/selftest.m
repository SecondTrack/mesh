// selftest.m — nativer Korrektheits-Check der SDK-unabhängigen Logik (läuft auf dem Mac,
// kein iOS-SDK/Emulator/iPod nötig). Tier 1 immer; Tier 2 (secp256k1) via -DMESH_HAVE_SECP.
//
// Bauen/Ausführen: tools/selftest.sh
#import <Foundation/Foundation.h>
#import "MeshHex.h"
#import "MeshBech32.h"
#import "MeshCrypto.h"
#ifdef MESH_HAVE_SECP
#import "MeshKeys.h"
#import "MeshEvent.h"
#import "MeshNip04.h"
#endif

static int g_fail = 0, g_pass = 0;
static void ok(BOOL cond, NSString *name) {
    if (cond) { g_pass++; printf("  ok   %s\n", name.UTF8String); }
    else      { g_fail++; printf("  FAIL %s\n", name.UTF8String); }
}

int main(int argc, char **argv) {
    @autoreleasepool {
        printf("== Mesh selftest ==\n");

        // ---- Hex ----
        NSData *raw = [MeshHex decode:@"00ff10ab"];
        ok(raw.length == 4, @"hex decode length");
        ok([[MeshHex encode:raw] isEqualToString:@"00ff10ab"], @"hex roundtrip");
        ok([MeshHex decode:@"xyz"] == nil, @"hex rejects invalid");

        // ---- SHA-256 (Vektor: sha256("abc")) ----
        NSData *sha = [MeshCrypto sha256:[@"abc" dataUsingEncoding:NSUTF8StringEncoding]];
        ok([[MeshHex encode:sha] isEqualToString:
            @"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"], @"sha256(abc) vector");

        // ---- AES-256-CBC Roundtrip ----
        NSData *key = [MeshCrypto randomBytes:32];
        NSData *iv  = [MeshCrypto randomBytes:16];
        NSData *pt  = [@"Mesh über Nostr — äöü 😀" dataUsingEncoding:NSUTF8StringEncoding];
        NSData *ct  = [MeshCrypto aes256cbcEncrypt:pt key:key iv:iv];
        NSData *back= [MeshCrypto aes256cbcDecrypt:ct key:key iv:iv];
        ok([back isEqualToData:pt], @"AES-256-CBC roundtrip");

        // ---- Bech32: autoritative BIP-173-Vektoren ----
        NSString *hrp = nil;
        ok([[MeshBech32 encodeHrp:@"a" data:[NSData data]] isEqualToString:@"a12uel5l"],
           @"bech32 BIP-173 a12uel5l");
        NSData *d20 = [MeshBech32 decode:@"abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw" hrp:&hrp];
        ok(d20.length == 20 && [hrp isEqualToString:@"abcdef"], @"bech32 BIP-173 decode 20 bytes");
        ok([[MeshBech32 encodeHrp:@"abcdef" data:d20] isEqualToString:
            @"abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw"], @"bech32 BIP-173 re-encode");

        // ---- Bech32: NIP-19-Paar (fiatjafs npub) ----
        NSString *npubHex = @"3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d";
        NSString *npub    = @"npub180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsyjh6w6";
        ok([[MeshBech32 encodeHrp:@"npub" data:[MeshHex decode:npubHex]] isEqualToString:npub],
           @"bech32 encode npub (NIP-19)");
        NSData *dec = [MeshBech32 decode:npub hrp:&hrp];
        ok([[MeshHex encode:dec] isEqualToString:npubHex] && [hrp isEqualToString:@"npub"],
           @"bech32 decode npub (NIP-19)");
        ok([MeshBech32 decode:@"npub180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsyjh6w7" hrp:NULL] == nil,
           @"bech32 rejects bad checksum");

#ifdef MESH_HAVE_SECP
        // ---- secp256k1: Identität + npub-Ableitung über Bech32 ----
        MeshKeys *k = [MeshKeys generate];
        ok(k != nil && k.xonlyPub.length == 32, @"keys generate");
        NSString *myNpub = [MeshBech32 encodeHrp:@"npub" data:k.xonlyPub];
        ok([[MeshBech32 decode:myNpub hrp:NULL] isEqualToData:k.xonlyPub], @"npub roundtrip of my key");

        // ---- Schnorr sign/verify + Manipulation ----
        NSData *msg = [MeshCrypto sha256:[@"hallo" dataUsingEncoding:NSUTF8StringEncoding]];
        NSData *sig = [k schnorrSign:msg];
        ok(sig.length == 64, @"schnorr sign len");
        ok([MeshKeys schnorrVerify:sig msg32:msg xonlyPub:k.xonlyPub], @"schnorr verify ok");
        NSData *badMsg = [MeshCrypto sha256:[@"hallO" dataUsingEncoding:NSUTF8StringEncoding]];
        ok(![MeshKeys schnorrVerify:sig msg32:badMsg xonlyPub:k.xonlyPub], @"schnorr rejects tampered");

        // ---- Event: signieren -> verify() true, ID stimmt ----
        MeshEvent *e = [MeshEvent kind:1 content:@"gm" tags:@[]];
        ok([e signWithKeys:k], @"event sign");
        ok([e verify], @"event verify");
        ok(e.eventId.length == 64 && e.sig.length == 128, @"event id/sig lengths");

        // ---- NIP-04 Roundtrip zwischen zwei Identitäten ----
        MeshKeys *a = [MeshKeys generate];
        MeshKeys *b = [MeshKeys generate];
        NSString *secret = @"Treffpunkt 20 Uhr 🕗";
        NSString *box = [MeshNip04 encrypt:secret keys:a peerXonlyPub:b.xonlyPub];
        NSString *out = [MeshNip04 decrypt:box keys:b peerXonlyPub:a.xonlyPub];
        ok([out isEqualToString:secret], @"NIP-04 A->B roundtrip");
        // ECDH-Symmetrie
        ok([[a ecdhSharedX:b.xonlyPub] isEqualToData:[b ecdhSharedX:a.xonlyPub]], @"ECDH symmetric");
#else
        printf("  (secp256k1 nicht gelinkt -> Tier 2 übersprungen; brew install secp256k1)\n");
#endif

        printf("== %d ok, %d fehlgeschlagen ==\n", g_pass, g_fail);
        return g_fail ? 1 : 0;
    }
}
