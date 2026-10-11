// Anhängen wie in der Android-App: Kamera, Foto, Video (MP4, kurz), Kontakt teilen.
#import <UIKit/UIKit.h>

@interface MeshAttachMenu : NSObject
// replyTo liefert beim Senden die zitierte cmid (oder nil); sent läuft nach erfolgreichem Senden.
+ (void)showFrom:(UIViewController *)host peer:(NSString *)peerHex
         replyTo:(NSString *(^)(void))replyTo sent:(void (^)(void))sent;
+ (void)pickImageFrom:(UIViewController *)host source:(UIImagePickerControllerSourceType)source peer:(NSString *)peerHex
              replyTo:(NSString *(^)(void))replyTo sent:(void (^)(void))sent;
@end
