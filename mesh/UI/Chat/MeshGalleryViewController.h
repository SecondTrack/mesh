// Medien eines Chats wie in der Android-App: alle Bilder und Videos als Raster, neueste zuerst.
// Antippen öffnet MeshMediaViewer. Von nicht angenommenen Kontakten nur die eigenen.
#import <UIKit/UIKit.h>

@interface MeshGalleryViewController : UIViewController
- (instancetype)initWithPeer:(NSString *)peerHex;
+ (NSArray *)itemsFor:(NSString *)peerHex;     // MeshMessage (Bilder, Videos), neueste zuerst
+ (NSUInteger)countFor:(NSString *)peerHex;   // für "Medien · N" im Kontaktprofil
@end
