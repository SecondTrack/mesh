#import "MeshVerifiedEvents.h"

@implementation MeshVerifiedEvents {
    NSMutableSet *_ids;
    NSLock *_lock;
}
static const NSUInteger kVerifiedMax = 4000;
- (instancetype)init {
    if ((self = [super init])) { _ids = [NSMutableSet set]; _lock = [[NSLock alloc] init]; }
    return self;
}
- (BOOL)containsId:(NSString *)eventId {
    [_lock lock]; BOOL hit = [_ids containsObject:eventId]; [_lock unlock];
    return hit;
}
- (void)addId:(NSString *)eventId {
    if (!eventId) return;
    [_lock lock];
    if (_ids.count >= kVerifiedMax) [_ids removeAllObjects];
    [_ids addObject:eventId];
    [_lock unlock];
}
- (void)reset { [_lock lock]; [_ids removeAllObjects]; [_lock unlock]; }
@end
