// Empfangene Datei öffnen, aber nur, was ein eigener, geprüfter Weg anzeigen kann:
//   JPEG/PNG (MeshMediaCheck, eigene Bildanzeige), Text (UTF-8, eigene Textansicht),
//   MP4-Video im System-Player (wie Bilder nur von angenommenen Kontakten, das prüft der Chat).
// Alles andere (PDF, Office, HTML …) bleibt zu: die Parser von iOS 6 (QuickLook, WebKit) haben
// bekannte Lücken, und HTML/Office würde am Transport vorbei aus dem Netz nachladen.
// Videos liegen dafür kurz entschlüsselt im tmp-Ordner (Dateischutz), gelöscht beim Schließen,
// beim Sperren und spätestens beim nächsten Start.
#import <UIKit/UIKit.h>

@interface MeshFileViewer : NSObject
+ (BOOL)isVideo:(NSData *)data mime:(NSString *)mime;   // nach Inhalt (ftyp) und MIME: Video-Kachel im Chat
+ (BOOL)canOpen:(NSData *)data mime:(NSString *)mime;
+ (void)open:(NSData *)data name:(NSString *)name mime:(NSString *)mime from:(UIViewController *)host;
@end
