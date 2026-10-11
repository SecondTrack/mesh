// Videos für den Versand: als MP4 in niedriger Qualität (spielt auch die Android-App ab).
// Die Quelldatei wird danach gelöscht; nichts bleibt unverschlüsselt im tmp-Ordner. Metadaten der
// Aufnahme (GPS-Ort, Gerät, Zeit) werden nicht übernommen.
#import <UIKit/UIKit.h>

@interface MeshVideoCodec : NSObject
// done auf dem Main-Thread: MP4-Daten oder nil (Fehler oder größer als maxBytes).
+ (void)mp4FromMovie:(NSURL *)movie maxBytes:(NSUInteger)maxBytes done:(void (^)(NSData *mp4))done;
// Vorschaubild (erstes Bild, längste Seite höchstens maxSide) für die Video-Kachel im Chat. Die
// Datei liegt dafür kurz geschützt im tmp-Ordner und wird sofort gelöscht. nil, wenn es nicht geht.
+ (UIImage *)thumbnailOfMP4:(NSData *)mp4 maxSide:(CGFloat)maxSide;
@end
