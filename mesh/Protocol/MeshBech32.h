// Bech32 (BIP-173) für NIP-19: npub/nsec aus 32-Byte-Keys.
// (Nur die einfachen bech32-Entities, kein TLV/nprofile.)
#import <Foundation/Foundation.h>

@interface MeshBech32 : NSObject
// hrp z.B. @"npub"/@"nsec"; data = die rohen 32 Bytes. -> "npub1..." / nil.
+ (NSString *)encodeHrp:(NSString *)hrp data:(NSData *)data;
// "npub1..." -> rohe Bytes; setzt *hrpOut auf "npub". nil bei ungültiger Prüfsumme.
+ (NSData *)decode:(NSString *)str hrp:(NSString **)hrpOut;
@end
