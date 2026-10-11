// Ein Nostr-Event (NIP-01). ID = sha256 der kanonischen Serialisierung,
// Signatur = Schnorr über die ID.
#import <Foundation/Foundation.h>
@class MeshKeys;

@interface MeshEvent : NSObject
@property (nonatomic, copy)   NSString *eventId;   // 32-Byte hex
@property (nonatomic, copy)   NSString *pubkey;    // 32-Byte hex (x-only)
@property (nonatomic, assign) long long createdAt; // Unix-Sekunden
@property (nonatomic, assign) NSInteger kind;
@property (nonatomic, copy)   NSArray *tags;       // Array von Arrays aus NSString
@property (nonatomic, copy)   NSString *content;
@property (nonatomic, copy)   NSString *sig;       // 64-Byte hex

// Unsigniertes Event bauen.
+ (instancetype)kind:(NSInteger)kind content:(NSString *)content tags:(NSArray *)tags;

// Gibt es einen Tag [name, value, …]? (z.B. "p" mit dem Empfänger)
- (BOOL)hasTag:(NSString *)name value:(NSString *)value;

// pubkey/createdAt setzen, ID berechnen, signieren. NO bei Fehler.
- (BOOL)signWithKeys:(MeshKeys *)keys;

// Prüft ID-Neuberechnung + Schnorr-Signatur.
- (BOOL)verify;

// Wire-Form (Dictionary) <-> Event.
- (NSDictionary *)toJSONObject;
+ (instancetype)fromJSONObject:(NSDictionary *)obj;
@end
