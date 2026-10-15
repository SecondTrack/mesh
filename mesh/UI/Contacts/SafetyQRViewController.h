// Eigener Sicherheits-Code als QR, damit der Kontakt ihn scannt (statt 60 Ziffern vorzulesen).
#import <UIKit/UIKit.h>

@interface SafetyQRViewController : UIViewController
- (instancetype)initWithPayload:(NSString *)payload peerName:(NSString *)name;
@end
