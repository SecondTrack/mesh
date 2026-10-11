// Langes Drücken auf eine Nachricht, wie in der Android-App: Nachrichten des Kontakts bekommen
// Reaktionen und "Antworten", eigene "Für alle löschen". Kopieren nur bei Text.
#import <Foundation/Foundation.h>
@class MeshMessage;

@interface MeshMessageMenu : NSObject
+ (void)showFor:(MeshMessage *)message peer:(NSString *)peerHex reply:(void (^)(void))reply;
+ (NSArray *)reactions;   // Auswahl, gleiche Reihenfolge wie Android
@end
