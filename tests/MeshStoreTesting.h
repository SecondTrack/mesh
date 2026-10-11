// Kurzform zum Einfügen in Tests (nur Richtung, Zeit, Event-ID). Nur in eine Testdatei je Binary einbinden.
#import "MeshStore.h"
#import "MeshMessage.h"

@interface MeshStore (Testing)
- (BOOL)insertMessageChat:(NSString *)chat fromMe:(BOOL)fromMe content:(NSString *)content ts:(long long)ts eventId:(NSString *)eventId;
@end

@implementation MeshStore (Testing)
- (BOOL)insertMessageChat:(NSString *)chat fromMe:(BOOL)fromMe content:(NSString *)content ts:(long long)ts eventId:(NSString *)eventId {
    MeshMessage *m = [[MeshMessage alloc] init];
    m.fromMe = fromMe; m.ts = ts; m.eventId = eventId;
    return [self insertMessage:m chat:chat content:content] != 0;
}
@end
