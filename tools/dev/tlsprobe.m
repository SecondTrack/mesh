// tlsprobe.m — läuft auf dem iPod (per SSH): verbindet MeshTLS + MeshWebSocket mit jedem Relay
// und meldet Erfolg oder den mbedTLS-Fehler. cacert.pem muss neben dem Programm liegen.
//   tools/dev/build-tlsprobe.sh  →  /tmp/tlsprobe  →  per scp aufs Gerät
#import <Foundation/Foundation.h>
#import "MeshWebSocket.h"

int main(int argc, char **argv) { @autoreleasepool {
    NSArray *hosts = argc > 1 ? [[NSProcessInfo processInfo].arguments subarrayWithRange:NSMakeRange(1, argc - 1)]
                              : @[ @"relay.primal.net", @"relay.snort.social", @"nos.lol", @"nostr.mom" ];
    int failed = 0;
    for (NSString *h in hosts) {
        MeshWebSocket *ws = [[MeshWebSocket alloc] init];
        NSString *err = nil;
        NSDate *t0 = [NSDate date];
        BOOL ok = [ws connectHost:h port:443 path:@"/" error:&err];
        printf("%-22s %s (%.1f s)\n", h.UTF8String, ok ? "OK" : (err ?: @"Fehler").UTF8String, -[t0 timeIntervalSinceNow]);
        if (ok) [ws close]; else failed++;
    }
    return failed;
}}
