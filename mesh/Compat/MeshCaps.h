// Was das Gerät kann. Die UI fragt nur hier nach, nie direkt nach Modell oder iOS-Version.
//
//   iPod touch 2G/3G: keine Kamera, Mikrofon nur mit Headset
//   iPod touch 4G, iPhone 3GS: Kamera und Mikrofon
#import <Foundation/Foundation.h>

@interface MeshCaps : NSObject
+ (BOOL)hasCamera;          // Rückkamera für QR-Scan und Fotos
+ (BOOL)hasMicrophone;      // jetzt verfügbar (beim iPod 2G/3G nur mit eingestecktem Headset)
@end
