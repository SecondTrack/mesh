// secp256k1-Schlüssel für Nostr: 32-Byte-Privkey, x-only-Pubkey (BIP-340),
// Schnorr-Signatur und -Prüfung, ECDH-Shared-X für NIP-04. Nutzt vendor/secp256k1
// (Module schnorrsig, extrakeys, ecdh).
#import <Foundation/Foundation.h>

@interface MeshKeys : NSObject

@property (nonatomic, readonly) NSData *seckey;   // 32 Byte, jedes Mal eine Kopie: nach Gebrauch MeshWipe
@property (nonatomic, readonly) NSData *xonlyPub; // 32 Byte (x-only, das Nostr-"pubkey"-Feld)

// Neue zufällige Identität / aus 32-Byte-Privkey. nil bei ungültigem Key.
+ (instancetype)generate;
+ (instancetype)fromSeckey:(NSData *)sk;

// Schnorr-Signatur (BIP-340) über 32-Byte-Nachricht (= Event-ID). 64 Byte, nil bei Fehler.
- (NSData *)schnorrSign:(NSData *)msg32;

// Verify: Signatur64 über msg32 gegen x-only-Pubkey (32 Byte).
+ (BOOL)schnorrVerify:(NSData *)sig64 msg32:(NSData *)msg32 xonlyPub:(NSData *)pub32;

// HMAC-SHA256(Seckey, label): leitet weitere Schlüssel ab, ohne den Seckey herauszugeben.
- (NSData *)derivedKey:(NSString *)label;
- (void)wipe;   // Seckey überschreiben; danach scheitert jede Signatur

// ECDH-Shared-Secret für NIP-04: rohe X-Koordinate (32 Byte) aus meinem Privkey + Peer-x-only-Pubkey.
- (NSData *)ecdhSharedX:(NSData *)peerXonlyPub32;

@end
