// Hex <-> Bytes. Nostr redet überall in Lowercase-Hex (Pubkeys, Event-IDs, Sigs).
#import <Foundation/Foundation.h>

@interface MeshHex : NSObject
+ (NSString *)encode:(NSData *)data;            // bytes -> "a1b2..."
+ (NSData *)decode:(NSString *)hex;             // "a1b2..." -> bytes, nil bei ungerader/ungültiger Länge
@end
