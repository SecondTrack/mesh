#import "MeshReachability.h"
#import "MeshNotifications.h"
#import <SystemConfiguration/SystemConfiguration.h>
#include <netinet/in.h>

@implementation MeshReachability {
    SCNetworkReachabilityRef _ref;
    BOOL _known, _reachable;
}

+ (instancetype)shared {
    static MeshReachability *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[MeshReachability alloc] init]; });
    return s;
}

+ (BOOL)reachableForFlags:(uint32_t)flags {
    if (!(flags & kSCNetworkReachabilityFlagsReachable)) return NO;
    if (!(flags & kSCNetworkReachabilityFlagsConnectionRequired)) return YES;
    // Verbindung auf Anforderung (VPN o. ä.), ohne dass der Nutzer etwas tun muss
    return (flags & (kSCNetworkReachabilityFlagsConnectionOnDemand | kSCNetworkReachabilityFlagsConnectionOnTraffic))
        && !(flags & kSCNetworkReachabilityFlagsInterventionRequired);
}

- (BOOL)reachable { return !_known || _reachable; }

- (void)apply:(SCNetworkReachabilityFlags)flags {
    BOOL now = [MeshReachability reachableForFlags:flags];
    if (_known && now == _reachable) return;
    _known = YES;
    _reachable = now;
    [[NSNotificationCenter defaultCenter] postNotificationName:MeshReachabilityChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] postNotificationName:MeshConnectionChangedNotification object:nil];
}

static void changed(SCNetworkReachabilityRef ref, SCNetworkReachabilityFlags flags, void *info) {
    [(__bridge MeshReachability *)info apply:flags];
}

- (void)start {
    if (_ref) return;
    struct sockaddr_in zero = { 0 };
    zero.sin_len = sizeof(zero);
    zero.sin_family = AF_INET;
    _ref = SCNetworkReachabilityCreateWithAddress(kCFAllocatorDefault, (const struct sockaddr *)&zero);
    if (!_ref) return;
    SCNetworkReachabilityContext ctx = { 0, (__bridge void *)self, NULL, NULL, NULL };   // Singleton, lebt immer
    SCNetworkReachabilitySetCallback(_ref, changed, &ctx);
    SCNetworkReachabilityScheduleWithRunLoop(_ref, CFRunLoopGetMain(), kCFRunLoopCommonModes);
    SCNetworkReachabilityFlags flags = 0;
    if (SCNetworkReachabilityGetFlags(_ref, &flags)) [self apply:flags];
}

@end
