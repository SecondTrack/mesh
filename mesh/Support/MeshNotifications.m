#import "MeshNotifications.h"

NSString *const MeshMessagesChangedNotification   = @"MeshMessagesChanged";
NSString *const MeshConnectionChangedNotification = @"MeshConnectionChanged";
NSString *const MeshTransportChangedNotification  = @"MeshTransportChanged";
NSString *const MeshProfilesChangedNotification   = @"MeshProfilesChanged";
NSString *const MeshProfilePubkey                 = @"pubkey";
NSString *const MeshWillLockNotification          = @"MeshWillLock";
NSString *const MeshWipedNotification             = @"MeshWiped";
NSString *const MeshIdentityChangedNotification   = @"MeshIdentityChanged";
NSString *const MeshIncomingMessageNotification   = @"MeshIncomingMessage";
NSString *const MeshIncomingName = @"name", *const MeshIncomingPreview = @"preview", *const MeshIncomingKind = @"kind";
