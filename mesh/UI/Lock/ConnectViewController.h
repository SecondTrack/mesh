// Startbildschirm nach dem Entsperren: Logo, Leitspruch und eine
// Netzwerk-Animation, die den echten Verbindungsstand der Relays zeigt.
#import <UIKit/UIKit.h>

@interface ConnectViewController : UIViewController
@property (nonatomic, copy) void (^onDone)(void);   // weiter zur Chatliste (nur wenn noch entsperrt)
@property (nonatomic) BOOL inspect;                   // aus der Leiste geöffnet: bleibt offen, Antippen schließt
- (void)cancel;                                       // Timer und Beobachter beenden, onDone nie mehr aufrufen
@end
