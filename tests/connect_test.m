// Ohne WLAN (0.1.36): Startbildschirm geht nach kurzem Hinweis bzw. spätestens nach kConnectMaxWait
// weiter (MeshConnectPolicy); Netz-Erkennung aus den SCNetworkReachability-Flags (MeshReachability).
#import "MeshTest.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import "MeshConnectPolicy.h"
#import "MeshReachability.h"

static NSTimeInterval leave(NSTimeInterval t, BOOL reach, BOOL up, BOOL failed) {
    return [MeshConnectPolicy leaveInAfter:t reachable:reach connected:up torFailed:failed];
}

static void testPolicy(void) {
    check(leave(0, NO, NO, NO) <= 2 && leave(0, NO, NO, NO) > 0.5, "ohne WLAN: kurz Hinweis zeigen, höchstens 2 s");
    check(leave(1, NO, NO, NO) <= 1, "ohne WLAN: Zeit läuft ab Erscheinen");
    check(leave(5, NO, NO, NO) == 0, "WLAN geht später weg: sofort weiter");
    check(leave(0, YES, NO, NO) == kConnectMaxWait && kConnectMaxWait <= 10, "Tor lädt: spätestens nach ~8 s weiter");
    check(leave(6, YES, NO, NO) == kConnectMaxWait - 6, "Höchstzeit zählt ab Erscheinen, nicht ab letztem Fortschritt");
    check(leave(20, YES, NO, NO) == 0, "nach der Höchstzeit sofort");
    check(leave(0, YES, YES, NO) < 1, "verbunden: kurz zeigen, dann weiter");
    check(leave(0, NO, YES, NO) < 1, "verbunden schlägt Netz-Meldung");
    check(leave(0, YES, NO, YES) < kConnectMaxWait && leave(0, YES, NO, YES) >= 2, "Tor gescheitert: Meldung lesbar, dann weiter");
    check(leave(7.5, YES, NO, YES) <= 0.5, "auch dann nie über die Höchstzeit");
}

static void testFlags(void) {
    check(![MeshReachability reachableForFlags:0], "keine Flags: kein Netz");
    check([MeshReachability reachableForFlags:kSCNetworkReachabilityFlagsReachable], "erreichbar");
    check(![MeshReachability reachableForFlags:kSCNetworkReachabilityFlagsReachable | kSCNetworkReachabilityFlagsConnectionRequired],
          "Verbindung nötig (WLAN aus/nicht verbunden): kein Netz");
    check([MeshReachability reachableForFlags:kSCNetworkReachabilityFlagsReachable | kSCNetworkReachabilityFlagsConnectionRequired
                                              | kSCNetworkReachabilityFlagsConnectionOnTraffic], "Verbindung auf Anforderung: Netz");
    check(![MeshReachability reachableForFlags:kSCNetworkReachabilityFlagsReachable | kSCNetworkReachabilityFlagsConnectionRequired
                                               | kSCNetworkReachabilityFlagsConnectionOnDemand | kSCNetworkReachabilityFlagsInterventionRequired],
          "braucht Eingriff des Nutzers: kein Netz");
    check([MeshReachability shared].reachable, "ungestartet: unbekannt gilt als erreichbar (kein falscher Offline-Hinweis)");
}

int main(void) {
    @autoreleasepool {
        testPolicy();
        testFlags();
    }
    return testsDone();
}
