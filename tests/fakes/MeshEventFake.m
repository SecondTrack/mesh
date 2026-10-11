// Ersetzt MeshEvent im Pool-Test: nur Datenfelder, keine Signatur (kein secp256k1 nötig).
#import "MeshEvent.h"

@implementation MeshEvent
+ (instancetype)kind:(NSInteger)kind content:(NSString *)content tags:(NSArray *)tags {
    MeshEvent *e = [self new];
    e.kind = kind; e.content = content; e.tags = tags;
    return e;
}
- (BOOL)hasTag:(NSString *)name value:(NSString *)value { return NO; }
- (BOOL)signWithKeys:(MeshKeys *)keys { return NO; }
- (BOOL)verify { return NO; }
- (NSDictionary *)toJSONObject { return nil; }
+ (instancetype)fromJSONObject:(NSDictionary *)obj { return nil; }
@end
