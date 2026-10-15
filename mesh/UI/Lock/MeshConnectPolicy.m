#import "MeshConnectPolicy.h"

const NSTimeInterval kConnectMaxWait = 8, kConnectOfflineShow = 1.5;
static const NSTimeInterval kShowConnected = 0.8, kShowFailed = 2.5;

@implementation MeshConnectPolicy

+ (NSTimeInterval)leaveInAfter:(NSTimeInterval)elapsed reachable:(BOOL)reachable connected:(BOOL)connected
                     torFailed:(BOOL)torFailed {
    NSTimeInterval cap = MAX(0, kConnectMaxWait - elapsed);
    NSTimeInterval wait = connected ? kShowConnected          // verbunden: kurz zeigen
                        : !reachable ? MAX(0, kConnectOfflineShow - elapsed)
                        : torFailed ? kShowFailed               // Meldung lesen lassen
                        : cap;
    return MIN(wait, cap);
}

@end
