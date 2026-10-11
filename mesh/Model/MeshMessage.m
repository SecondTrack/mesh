#import "MeshMessage.h"

@implementation MeshMessage

- (NSString *)key { return self.cmid.length ? self.cmid : self.eventId; }

@end
