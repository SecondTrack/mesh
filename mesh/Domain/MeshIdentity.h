// Eine Identität (wie ein Slot der Android-App, MeshCore.Session): eigene Datenbank mit Vault,
// Kontakten und Nachrichten, eigener Signal-Zustand. Alle Identitäten teilen PIN, Gerätegeheimnis
// und Relay-Verbindungen; empfangen wird für alle gleichzeitig.
//
// Welche es gibt und welche angezeigt wird, steht unverschlüsselt in den NSUserDefaults (nur die
// Nummern, wie IdentityManager.kt). Nummer 0 ist die ursprüngliche Datenbank mesh.sqlite.
#import <Foundation/Foundation.h>
@class MeshStore, MeshVault, MeshKeys, MeshMessenger, MeshSignal, MeshInboxPolicy, MeshPanic, MeshTeam;
@protocol MeshMessengerDelegate;

@interface MeshIdentity : NSObject
+ (NSArray *)savedSlots;                 // NSNumber, mindestens @[@0]
+ (int)activeSlot;
+ (void)saveSlots:(NSArray *)slots active:(int)active;
+ (NSString *)databasePathForSlot:(int)slot;

- (instancetype)initWithSlot:(int)slot;  // öffnet die Datenbank (gesperrt)
@property (nonatomic, readonly) int slot;
@property (nonatomic, readonly) MeshStore *store;
@property (nonatomic, readonly) MeshVault *vault;
@property (nonatomic, readonly) MeshInboxPolicy *inbox;

// Nur entsperrt:
@property (nonatomic, readonly) MeshKeys *keys;
@property (nonatomic, readonly) MeshMessenger *messenger;
@property (nonatomic, readonly) MeshSignal *signal;
@property (nonatomic, readonly) NSString *pubkey;
@property (nonatomic, readonly) MeshTeam *team;          // nil, wenn der Team-Chat aus ist (MeshTeam)
- (void)unlockWithKeys:(MeshKeys *)keys panic:(MeshPanic *)panic delegate:(id<MeshMessengerDelegate>)delegate;
- (void)lock;
- (BOOL)destroy;                         // Datenbank löschen (Notlöschung, Zurücksetzen)
@end
