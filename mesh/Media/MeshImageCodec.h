// Bilder vor dem Versenden verkleinern und als JPEG kodieren.
// Klein halten: Nostr-Events gehen als Base64 durch öffentliche Relays.
#import <UIKit/UIKit.h>

#import "MeshMediaCheck.h"

@interface MeshImageCodec : NSObject
// Fremde Bilddaten: erst Format und Größe prüfen (MeshMediaCheck), dann dekodieren. nil bei Ablehnung.
+ (UIImage *)imageFromData:(NSData *)data formats:(MeshImageFormats)formats;

// Profilbild in gespeicherter Form (Base64 oder data:-URI) → Bild. http(s) wird bewusst nicht
// geladen (kein Netzzugriff an Tor vorbei). Gecacht; der Cache wird beim Sperren geleert.
+ (UIImage *)imageFromPicture:(NSString *)picture;
+ (NSString *)pictureFromJPEG:(NSData *)jpeg;   // für MeshProfile picture

+ (NSData *)jpegForChat:(UIImage *)image;     // längste Seite höchstens 480 px
+ (NSData *)jpegForAvatar:(UIImage *)image;   // kürzeste Seite 256 px
@end
