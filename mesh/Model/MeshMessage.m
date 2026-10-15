#import "MeshMessage.h"
#include <time.h>

NSString *const MeshSenderAll = @"all", *const MeshSenderApp = @"app";

@implementation MeshMessage

- (NSString *)key { return self.cmid.length ? self.cmid : self.eventId; }

@end

const long long kMeshRunGap = 3 * 60;

static BOOL inRun(MeshMessage *m) { return !m.fromMe && m.kind != MeshPayloadNotice && m.sender.length; }

static BOOL sameDay(long long a, long long b) {
    time_t ta = (time_t)a, tb = (time_t)b;
    struct tm x, y;
    if (!localtime_r(&ta, &x) || !localtime_r(&tb, &y)) return NO;
    return x.tm_year == y.tm_year && x.tm_yday == y.tm_yday;
}

// a direkt vor b: gleiche Folge?
static BOOL together(MeshMessage *a, MeshMessage *b) {
    return inRun(a) && inRun(b) && [a.sender isEqualToString:b.sender] && llabs(b.ts - a.ts) <= kMeshRunGap && sameDay(a.ts, b.ts);
}

MeshRunPosition MeshRunPositionAt(NSArray *messages, NSUInteger i) {
    if (i >= messages.count || !inRun(messages[i])) return MeshRunNone;
    MeshMessage *m = messages[i];
    MeshRunPosition p = MeshRunIn;
    if (i == 0 || !together(messages[i - 1], m)) p |= MeshRunFirst;
    if (i + 1 >= messages.count || !together(m, messages[i + 1])) p |= MeshRunLast;
    return p;
}
