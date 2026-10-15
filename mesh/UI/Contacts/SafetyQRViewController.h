// Eigener Sicherheits-Code als QR, damit der Kontakt ihn scannt (statt 60 Ziffern vorzulesen).
#import <UIKit/UIKit.h>

@interface SafetyQRViewController : UIViewController
- (instancetype)initWithPayload:(NSString *)payload peerName:(NSString *)name;
// Gleiche Ansicht für anderes (z.B. Gruppen-Link, B10): eigener Titel und Hinweis darunter.
- (instancetype)initWithPayload:(NSString *)payload title:(NSString *)title hint:(NSString *)hint;
@end
