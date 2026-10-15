// Wann der Startbildschirm (ConnectViewController) zur Chatliste weitergeht. Ohne UIKit (auf dem Mac
// getestet). Niemand bleibt dort hängen: ohne Netz nach kurzem Hinweis, sonst spätestens nach
// kConnectMaxWait, auch wenn Tor noch lädt (die Chatliste zeigt dann "verbindet …"). Am Senden ändert
// das nichts: Nachrichten warten in der Warteschlange, bis Tor und ein Relay stehen.
#import <Foundation/Foundation.h>

extern const NSTimeInterval kConnectMaxWait;       // höchstens so lange auf dem Startbildschirm
extern const NSTimeInterval kConnectOfflineShow;   // "Keine WLAN-Verbindung" so lange zeigen

@interface MeshConnectPolicy : NSObject
// Sekunden ab jetzt bis zum Weitergehen; elapsed = seit der Bildschirm erschienen ist.
+ (NSTimeInterval)leaveInAfter:(NSTimeInterval)elapsed reachable:(BOOL)reachable connected:(BOOL)connected
                     torFailed:(BOOL)torFailed;
@end
