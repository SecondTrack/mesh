// Signal-Protokoll für Mesh, wie MeshSignal.kt der Android-App (dort libsignal-protocol-java):
//
//  - Die Signal-Identität folgt aus dem nsec: Skalar = SHA-256("mesh:signal:id:v1" ‖ nsec), Registrierungs-ID
//    aus SHA-256("mesh:signal:reg:v1" ‖ nsec). Dieselbe npub ergibt also auf jedem Gerät dieselbe Identität.
//  - Ein signierter PreKey (ID 1) und Einmal-PreKeys für frische Bundles (die jüngsten 720 bleiben gültig).
//  - Verschlüsselte DMs tragen "sg1:p:<Base64>" (PreKeySignalMessage) bzw. "sg1:m:<Base64>" (SignalMessage).
//  - Vertrauen beim ersten Kontakt; ändert sich die Identität eines verifizierten Kontakts, wird sie
//    abgelehnt (dann NIP-44 an die npub), bei unverifizierten übernommen.
//
// Gespeichert wird über MeshSignalStorage (in der App: MeshStore+Signal, versiegelt).
#import <Foundation/Foundation.h>
#import "MeshSignalStorage.h"

extern NSString *const MeshSignalScheme;   // "sg1:"

@interface MeshSignal : NSObject
- (instancetype)initWithStorage:(id<MeshSignalStorage>)storage seed:(NSData *)nsec;   // nil ohne gültigen Seed

@property (nonatomic, readonly) NSData *identityKey;    // öffentlich, 32 Byte
- (NSString *)bundle;                                   // ohne Einmal-PreKey (z.B. für Kontaktkarten)
- (NSString *)bundleWithFreshOneTimeKey;                // für den QR-Code und die ersten Nachrichten

- (BOOL)hasSessionWith:(NSString *)peer;
// nil: keine Sitzung und kein brauchbares Bundle (dann darf NIP-44 einspringen), oder refused = YES:
// die Identität eines verifizierten Kontakts hat sich geändert (dann gar nicht senden).
- (NSString *)encrypt:(NSString *)plaintext to:(NSString *)peer bundle:(NSString *)peerBundle
             verified:(BOOL)verified refused:(BOOL *)refused;
- (NSString *)decrypt:(NSString *)content from:(NSString *)peer verified:(BOOL)verified;   // nil bei Fehler oder Doppel
- (void)forgetPeer:(NSString *)peer;                    // Sitzung und gemerkte Identität

+ (BOOL)bundle:(NSString *)a sameIdentityAs:(NSString *)b;
// Sicherheitsnummer wie Android: 12 Gruppen à 5 Ziffern, auf beiden Seiten gleich. nil ohne Bundle.
- (NSArray *)safetyNumberWith:(NSString *)peer myPubkey:(NSString *)myPubkey peerBundle:(NSString *)peerBundle;
@end
