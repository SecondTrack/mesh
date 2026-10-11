// Kamera-QR-Scanner (AVFoundation + gevendortes quirc).
// iOS 6 hat kein natives QR → wir dekodieren die Frames selbst.
#import <UIKit/UIKit.h>

@interface QRScannerViewController : UIViewController
@property (nonatomic, copy) void (^onScan)(NSString *payload);   // wird einmal mit dem Ergebnis aufgerufen
@property (nonatomic, copy) void (^onManual)(void);             // „Code einfügen" -> manuelle Eingabe
@end
