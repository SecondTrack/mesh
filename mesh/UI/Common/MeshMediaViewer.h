// Bilder und Videos eines Chats im Vollbild wie in der Android-App: wischen, zoomen (Doppeltippen
// oder zwei Finger), oben Absender, Datum und "n/N", unten Speichern und Löschen. Antippen blendet die
// Leisten aus. Dekodiert werden nur das gezeigte Bild und seine Nachbarn.
#import <UIKit/UIKit.h>

@interface MeshMediaViewer : UIViewController
// items: MeshMessage (Bild oder Video) in Anzeigereihenfolge; index: das zuerst gezeigte
- (instancetype)initWithItems:(NSArray *)items index:(NSUInteger)index peer:(NSString *)peerHex;
@end
