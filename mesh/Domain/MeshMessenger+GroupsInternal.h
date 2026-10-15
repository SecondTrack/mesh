// Gemeinsames der Gruppen-Dateien (MeshMessenger+Groups.m, MeshMessenger+GroupsOpen.m). Nur dort importieren.
#import "MeshMessenger+Internal.h"
#import "MeshStore+Group.h"
#import "MeshPayload.h"
#import "MeshEnvelope.h"
@class MeshGroupState, MeshEnvelope, MeshEvent;

static const NSUInteger kMaxGroups = 200;   // Einladungen und Link-Beitritte darüber hinaus verwerfen

// Gruppen-Event (Nachricht, Reaktion, Löschen), das vor dem passenden Zustand ankam (B8.4). Nur das
// Nötige: der entschlüsselte Umschlag, nicht das ganze Event.
@interface MeshPendingGroupEvent : NSObject
@property (nonatomic) MeshEnvelope *env;
@property (nonatomic, copy) NSString *from, *eventId;
@property (nonatomic) long long createdAt, arrived;
@property (nonatomic) NSUInteger bytes;
@end
@interface MeshMessenger (GroupHelpers)
- (BOOL)save:(MeshGroupState *)s status:(MeshGroupStatus)status inviter:(NSString *)inviter;
- (NSArray *)recipientsOf:(MeshGroupState *)s;
- (NSUInteger)sendControl:(NSString *)plain toAll:(NSArray *)peers;
- (void)notice:(MeshGroupNotice)event name:(NSString *)name gid:(NSString *)gid byMe:(BOOL)byMe;
- (BOOL)amAdminOf:(MeshGroupState *)s status:(MeshGroupStatus)status;
- (BOOL)publish:(MeshGroupState *)s extra:(NSString *)extra;
- (BOOL)receiveInvite:(MeshEnvelope *)env event:(MeshEvent *)event keep:(BOOL *)keep;
- (BOOL)applyInvite:(MeshGroupState *)s from:(NSString *)from;
- (BOOL)receiveState:(MeshGroupState *)s from:(NSString *)from;
- (BOOL)receiveJoin:(MeshEnvelope *)env from:(NSString *)from;
- (BOOL)receiveLeave:(NSString *)gid from:(NSString *)from;
- (BOOL)receiveGroupEvent:(MeshPendingGroupEvent *)p;
- (void)buffer:(MeshPendingGroupEvent *)p gid:(NSString *)gid;
- (BOOL)replayGroup:(NSString *)gid;
- (BOOL)receiveGroupPicture:(MeshEnvelope *)env from:(NSString *)from;
- (NSData *)storedPictureOf:(MeshGroupState *)s;
- (BOOL)receiveState:(MeshGroupState *)s from:(NSString *)from keep:(BOOL *)keep;
- (BOOL)receiveLeave:(NSString *)gid from:(NSString *)from keep:(BOOL *)keep;
- (BOOL)applyAdminLeave:(NSString *)gid from:(NSString *)from;
- (BOOL)storePicture:(NSData *)bytes gid:(NSString *)gid;
- (void)reconcilePictureOf:(MeshGroupState *)s joined:(BOOL)joined;
- (void)pictureChanged:(NSString *)gid;
@end

// In MeshMessenger (Groups) umgesetzt, von den Helfern mitbenutzt.
@interface MeshMessenger (GroupsShared)
- (void)holdInvite:(MeshGroupState *)s from:(NSString *)from eventId:(NSString *)eventId;
- (void)dropQueuedCopiesOf:(NSString *)gid;
- (BOOL)invite:(NSArray *)pubkeys toGroup:(NSString *)gid allowing:(NSString *)allowed;
- (NSString *)groupPlain:(NSString *)content gid:(NSString *)gid cmid:(NSString *)cmid replyTo:(NSString *)replyTo
                   timer:(int)timer mode:(MeshTimerMode)mode to:(NSString *)pk;
@end


// B9/B10, in MeshMessenger+GroupsOpen.m
@interface MeshMessenger (GroupsOpenInternal)
- (BOOL)maintainOpenGroups;                                    // beim Entsperren: Abgelaufenes, Aufgeschobenes
- (NSString *)voucherFor:(NSString *)gid admin:(NSString *)admin;   // Bürge (angenommener Kontakt) oder nil
- (void)forgetVouchersFor:(NSString *)gid;
- (void)forgetProposalsOf:(NSString *)pk gid:(NSString *)gid;
- (BOOL)linkJoinExpired:(NSString *)gid;
- (void)holdState:(MeshGroupState *)s from:(NSString *)from;   // RAM, eins je Gruppe, 15 min
- (void)holdLeave:(NSString *)gid from:(NSString *)from;       // RAM, gl des Admins, 15 min
- (void)stateApplied:(MeshGroupState *)s;                      // Wartendes neu prüfen
- (BOOL)receiveProposal:(MeshEnvelope *)env from:(NSString *)from;
- (BOOL)receiveVouch:(MeshEnvelope *)env from:(NSString *)from;
- (BOOL)receiveGroupKey:(MeshEnvelope *)env from:(NSString *)from keep:(BOOL *)keep;
@end
