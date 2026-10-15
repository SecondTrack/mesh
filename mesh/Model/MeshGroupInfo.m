#import "MeshGroupInfo.h"

@implementation MeshGroupInfo
- (BOOL)canWrite { return _status == MeshGroupMember; }
@end
