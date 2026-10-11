// "Kontakt senden" wie in der Android-App: Liste der angenommenen Kontakte mit Bild und Name,
// Antippen schickt die Kontakt-Karte und kehrt zum Chat zurück.
#import <UIKit/UIKit.h>

@interface ContactPickerViewController : UIViewController
- (instancetype)initWithPeer:(NSString *)peerHex sent:(void (^)(void))sent;   // an wen; sent nach dem Senden
@end
