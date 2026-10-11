// Zwischenablage, die jede App lesen kann. Öffentliche Daten (npub) bleiben dort; kopierter
// Nachrichtentext wird beim Sperren wieder entfernt, sofern er noch drinsteht. Der geheime
// Schlüssel wird nur angezeigt, nie kopiert.
#import <UIKit/UIKit.h>

@interface MeshClipboard : NSObject
+ (void)copyPublic:(NSString *)text confirmation:(NSString *)message;   // mit kurzer Rückmeldung
+ (void)copyMessage:(NSString *)text;                                    // bis zum Sperren
@end
