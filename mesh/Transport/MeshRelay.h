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
// Die Schreib-Warteschlange ist leer, nachdem ein großes Event abgelehnt wurde (publish: NO): jetzt nachreichen.
- (void)relayDidDrain:(MeshRelay *)relay;
@end

enum { MeshRelayQueueCap = 2 * 1024 * 1024, MeshRelayLargeEvent = 64 * 1024 };

@interface MeshRelay : NSObject
@property (nonatomic, mesh_weak) id<MeshRelayDelegate> delegate;
@property (nonatomic, readonly, copy) NSString *url;
@property (nonatomic, strong) MeshVerifiedEvents *verified;   // geteilt mit den anderen Relays der Gruppe (nil = keine)
@property (nonatomic, readonly) BOOL connected;
@property (nonatomic, readonly) BOOL connecting;     // Verbindungsaufbau läuft
@property (nonatomic, copy) NSString *socksCredential;   // gesetzt: eigener Tor-Kreis (MeshTLS), sonst nie verbinden

- (instancetype)initWithURL:(NSString *)wssUrl;   // "wss://relay.damus.io"
- (void)connect;
- (void)disconnect;

// REQ mit einem Filter (z.B. @{@"kinds":@[@4], @"#p":@[myHex]}).
- (void)subscribe:(NSString *)subId filter:(NSDictionary *)filter;
- (void)unsubscribe:(NSString *)subId;   // CLOSE: Relays begrenzen offene Abos je Verbindung

// Signiertes Event publizieren. NO: nicht verbunden oder großes Event (> MeshRelayLargeEvent), während
// schon mehr als MeshRelayQueueCap Bytes auf das Schreiben warten (je Relay eine eigene Kopie im RAM).
// Dann kommt relayDidDrain:, sobald die Warteschlange leer ist.
- (BOOL)publish:(MeshEvent *)event;
@property (nonatomic, readonly) long long queuedBytes;   // warten aufs Schreiben (für Tests und Pool)
- (void)notifyWhenDrained;                                // relayDidDrain:, sobald nichts mehr wartet

// NIP-42: signiertes Auth-Event (kind 22242) als ["AUTH", event] senden.
- (void)sendAuth:(MeshEvent *)authEvent;
@end
