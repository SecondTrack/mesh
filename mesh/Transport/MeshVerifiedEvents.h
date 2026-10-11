#import <Foundation/Foundation.h>

// Schon geprüft gelieferte Event-IDs einer Relay-Gruppe: Dieselbe DM kommt von jedem Relay, die
// Schnorr-Prüfung kostet am iPod spürbar. Eingetragen erst nach erfolgreicher Prüfung (eine
// gefälschte Kopie verdrängt nichts); threadsicher, die Relays lesen auf eigenen Threads.
@interface MeshVerifiedEvents : NSObject
- (BOOL)containsId:(NSString *)eventId;
- (void)addId:(NSString *)eventId;
- (void)reset;
@end
