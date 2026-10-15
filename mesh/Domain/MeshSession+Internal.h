// Was die Teile von MeshSession untereinander brauchen (MeshSession.m: Identitäten, Relays, Sperren;
// MeshSession+Pin.m: PIN und Notlöschung; MeshSession+Chats.m: Kontakte, Chats, Nachrichten).
// Nur innerhalb von Domain importieren.
#import "MeshSession.h"
#import "MeshMessenger.h"
@class MeshIdentity, MeshRelayPool, MeshEvent, MeshPanic, MeshPinGuard;

@interface MeshSession () <MeshMessengerDelegate>
@property (nonatomic) MeshIdentity *active;                    // angezeigte Identität
@property (nonatomic) NSMutableArray *allIdentities;           // MeshIdentity, nach Nummer sortiert
@property (nonatomic, readonly) MeshRelayPool *pool;
@property (nonatomic, readonly) MeshPinGuard *guard;
@property (nonatomic, readonly) MeshPanic *panic;
@property (nonatomic, readwrite) BOOL unlocked;
- (void)goOnline;                  // nach dem Entsperren: Uhren stellen, Relays verbinden
- (NSArray *)unlockedIdentities;   // MeshIdentity
- (void)messagesChanged;           // Uhren neu stellen, UI benachrichtigen
- (void)notify:(NSString *)name;
- (void)notifyProfileOf:(NSString *)pubkey;   // MeshProfilesChangedNotification nur für diesen Pubkey
- (void)requestProfileOf:(NSString *)hex;
@end

@interface MeshSession (PinInternal)
- (MeshPinResult)loadDeviceSecret;   // in MeshSession+Pin.m
- (NSString *)normalized:(NSString *)secret kind:(MeshSecretKind)kind;
@end

@interface MeshSession (PairingInternal)
- (void)receivePairingEvent:(MeshEvent *)event subId:(NSString *)subId;   // in MeshSession+Pairing.m
@end

@interface MeshSession (ChatsInternal)
- (BOOL)sendContent:(NSString *)content to:(NSString *)peerHex replyTo:(NSString *)replyTo;   // in MeshSession+Chats.m
@end
