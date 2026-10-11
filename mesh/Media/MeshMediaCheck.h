// Prüft fremde Bild- und Audiodaten, bevor sie ein System-Decoder sieht.
//
// Die Decoder von iOS 4–6 hatten ausnutzbare Lücken (TIFF, PDF, Schriften …), und
// [UIImage imageWithData:] nimmt jedes Format. Deshalb: nur JPEG/PNG bzw. M4A/ADTS durchlassen,
// Bildgröße aus dem Dateikopf lesen und begrenzen (Speicher eines 128-MB-Geräts).
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

typedef NS_OPTIONS(NSUInteger, MeshImageFormats) {
    MeshImageJPEG = 1 << 0,
    MeshImagePNG  = 1 << 1
};

extern const int MeshImageMaxSide;         // 2048
extern const int MeshImageMaxPixels;       // 2048 × 1536 (3,1 Megapixel, ~12 MB dekodiert)

@interface MeshMediaCheck : NSObject
// Breite/Höhe aus dem Dateikopf; CGSizeZero, wenn kein erlaubtes Format oder kaputt.
+ (CGSize)imageSize:(NSData *)data formats:(MeshImageFormats)formats;
// Erlaubtes Format und innerhalb der Grenzen.
+ (BOOL)isAcceptableImage:(NSData *)data formats:(MeshImageFormats)formats;
// M4A (ISO-BMFF mit ftyp) oder AAC-ADTS.
+ (BOOL)isAcceptableAudio:(NSData *)data;   // Struktur geprüft, nicht nur der Anfang
@end
