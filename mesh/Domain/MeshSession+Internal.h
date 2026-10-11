// Was die Teile von MeshSession untereinander brauchen (MeshSession.m: Identitäten, Relays, Sperren;
// MeshSession+Pin.m: PIN und Notlöschung; MeshSession+Chats.m: Kontakte, Chats, Nachrichten).
// Nur innerhalb von Domain importieren.
#import "MeshSession.h"
#import "MeshMessenger.h"
@class MeshIdentity, MeshRelayPool, MeshPanic, MeshPinGuard;

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
- (void)requestProfileOf:(NSString *)hex;
@end

@interface MeshSession (PinInternal)
- (MeshPinResult)loadDeviceSecret;   // in MeshSession+Pin.m
- (NSString *)normalized:(NSString *)secret kind:(MeshSecretKind)kind;
@end
