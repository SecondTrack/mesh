// QR-Codes in Kamerabildern finden (quirc, vendor/quirc).
// Nicht threadsicher: nur von einer Queue aus benutzen.
#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

@interface MeshQRDecoder : NSObject
// Erster lesbarer Code im Bild (BGRA) als Text, sonst nil.
- (NSString *)decodePixelBuffer:(CVPixelBufferRef)buffer;
@end
