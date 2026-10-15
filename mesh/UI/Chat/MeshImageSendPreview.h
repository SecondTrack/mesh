// Vorschau vor dem Senden eines Bildes, wie in der Android-App: das Bild so, wie es verschickt wird
// (verkleinert, ohne Metadaten), darunter Abbrechen und Senden.
#import <UIKit/UIKit.h>

@interface MeshImageSendPreview : UIViewController
- (instancetype)initWithJPEG:(NSData *)jpeg send:(void (^)(NSData *jpeg))send;
@end
