// Ist überhaupt ein Netz da (am iPod: WLAN)? SCNetworkReachability auf 0.0.0.0, wie Apples Beispiel,
// unter iOS 4–6 vorhanden. Nur für Anzeige und schnelleres Wiederverbinden: ob und wie gesendet wird,
// entscheidet weiter allein der Transport (mit Tor nie ohne Tor). Meldet Änderungen per
// MeshReachabilityChangedNotification und MeshConnectionChangedNotification. Alles auf dem Main-Thread.
#import <Foundation/Foundation.h>

@interface MeshReachability : NSObject
+ (instancetype)shared;
- (void)start;                                  // einmal; liest den Stand sofort (synchron)
@property (nonatomic, readonly) BOOL reachable; // YES, solange unbekannt (nicht gestartet)
// Entscheidung aus SCNetworkReachabilityFlags (Tests): erreichbar und ohne nötigen Verbindungsaufbau
// durch den Nutzer.
+ (BOOL)reachableForFlags:(uint32_t)flags;
@end
