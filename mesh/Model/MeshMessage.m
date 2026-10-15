#import "MeshMessage.h"

NSString *const MeshSenderAll = @"all", *const MeshSenderApp = @"app";

@implementation MeshMessage

- (NSString *)key { return self.cmid.length ? self.cmid : self.eventId; }

@end
