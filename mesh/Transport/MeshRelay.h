// Eine Verbindung zu einem Nostr-Relay über wss://. Lese-Loop auf eigenem Thread;
// Aufrufe und Delegate-Callbacks auf dem Main-Thread. Wiederverbinden regelt MeshRelayPool.
#import <Foundation/Foundation.h>
#import "MeshVerifiedEvents.h"
@class MeshEvent, MeshRelay;

@protocol MeshRelayDelegate <NSObject>
@optional
- (void)relayDidConnect:(MeshRelay *)relay;
- (void)relay:(MeshRelay *)relay didReceiveEvent:(MeshEvent *)event subId:(NSString *)subId;
- (void)relay:(MeshRelay *)relay didFinishStoredEvents:(NSString *)subId;         // EOSE
- (void)relay:(MeshRelay *)relay didGetOKForEvent:(NSString *)eventId accepted:(BOOL)ok message:(NSString *)msg;
- (void)relay:(MeshRelay *)relay didDisconnectWithError:(NSString *)err;
// NIP-42: Relay verlangt Login. Delegate baut ein signiertes kind-22242-Event und ruft -sendAuth:.
- (void)relay:(MeshRelay *)relay didRequestAuth:(NSString *)challenge;
@end

@interface MeshRelay : NSObject
@property (nonatomic, mesh_weak) id<MeshRelayDelegate> delegate;
@property (nonatomic, readonly, copy) NSString *url;
@property (nonatomic, strong) MeshVerifiedEvents *verified;   // geteilt mit den anderen Relays der Gruppe (nil = keine)
@property (nonatomic, readonly) BOOL connected;
@property (nonatomic, readonly) BOOL connecting;     // Verbindungsaufbau läuft

- (instancetype)initWithURL:(NSString *)wssUrl;   // "wss://relay.damus.io"
- (void)connect;
- (void)disconnect;

// REQ mit einem Filter (z.B. @{@"kinds":@[@4], @"#p":@[myHex]}).
- (void)subscribe:(NSString *)subId filter:(NSDictionary *)filter;

// Signiertes Event publizieren.
- (void)publish:(MeshEvent *)event;

// NIP-42: signiertes Auth-Event (kind 22242) als ["AUTH", event] senden.
- (void)sendAuth:(MeshEvent *)authEvent;
@end
