// Was MeshMessenger+Groups.m vom Messenger braucht. Nur in Domain/MeshMessenger*.m importieren.
#import "MeshMessenger.h"
@class MeshEnvelope;

@interface MeshMessenger ()
@property (nonatomic, readonly) MeshStore *store;
@property (nonatomic, readonly) MeshKeys *keys;
@property (nonatomic, readonly) NSMutableDictionary *pendingGroupPictures;   // gid -> Bildbytes (B7), nur RAM
@property (nonatomic, readonly) NSMutableDictionary *pendingGroupEvents;     // gid -> gepufferte Events (B8.4), nur RAM
@property (nonatomic, readonly) NSMutableDictionary *heldGroupControl;      // gid -> wartender Zustand/gl/gk (B9/B10), nur RAM
@property (nonatomic, readonly) NSMutableArray *fanoutJobs;                  // ausstehende Fan-out-Kopien (MeshMessenger+Groups)
- (void)scheduleFanout;
- (MeshEvent *)eventWith:(NSString *)plain to:(NSString *)peer;   // verschlüsselt und signiert, nil bei Fehler
- (void)discard:(MeshEvent *)event;                                // als erledigt merken (Tombstone)
- (void)discardId:(NSString *)eventId;
- (void)addNotice:(NSString *)content chat:(NSString *)chat byMe:(BOOL)byMe;
- (NSString *)ownBundleFor:(NSString *)peer;
@end

@interface MeshMessenger (GroupReceive)
- (BOOL)receiveGroup:(MeshEnvelope *)env event:(MeshEvent *)event;   // in MeshMessenger+Groups.m
- (void)fanoutStep;                                                   // eine Kopie der ältesten ausstehenden Nachricht
@end

// In MeshMessenger+GroupsOpen.m (B9/B10).
@interface MeshMessenger (GroupDeadlines)
- (BOOL)processGroupDeadlines;                       // abgelaufene Wartezeiten (gl des Admins ohne Übergabe)
- (NSTimeInterval)secondsUntilGroupDeadline;         // < 0: keine
- (BOOL)isValidGroupLinkCard:(NSString *)content;    // Link-Karte lesbar (Name, Link)
@end
