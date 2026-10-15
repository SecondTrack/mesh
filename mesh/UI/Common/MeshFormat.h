// Anzeigetexte für Zeiten, Vorschauen und Kontaktnamen.
#import <Foundation/Foundation.h>
#import "MeshSession.h"

@interface MeshFormat : NSObject
+ (NSString *)shortTime:(long long)ts;          // heute "HH:mm", sonst "dd.MM."
+ (NSString *)preview:(NSString *)content kind:(NSInteger)kind;   // eine Zeile; Medien als "Photo" / "Voice message"
+ (NSString *)timer:(int)seconds;
+ (NSString *)fileDetail:(NSString *)name mime:(NSString *)mime bytes:(long long)bytes;   // "PDF · 120 KB"              // "Off", "5 minutes", "1 day" …
+ (NSString *)notice:(NSString *)content peer:(NSString *)peerName;   // Hinweiszeile im Chat (MeshPayloadNotice)
+ (NSString *)duration:(int)seconds;           // "m:ss"
+ (NSString *)pinWait:(NSTimeInterval)seconds; // "Zu viele Versuche — wieder möglich in m:ss"
+ (NSString *)pinError:(MeshPinResult)result wait:(NSTimeInterval)wait;   // nil bei MeshPinOK
+ (NSString *)contactName:(NSString *)name accepted:(BOOL)accepted;   // nicht angenommen: "Unknown · Name"
// Zähler mit Einzahl: "1 member" / "3 members"; Medien in Gruppen nur Fotos (dort keine Videos)
+ (NSString *)members:(NSUInteger)n;
+ (NSString *)media:(NSUInteger)n photosOnly:(BOOL)photosOnly;
@end
