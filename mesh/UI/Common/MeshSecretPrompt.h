// Code bestätigen (nsec anzeigen, Notlöschung, Identitäten, Schutz ändern) mit demselben Bildschirm
// wie beim Öffnen der App: Ziffernblock bei der PIN, Wortfeld bei Wörtern, dazu "Abbrechen".
// next bekommt den geprüften Code; Fehlversuche zählen wie am Sperrbildschirm.
#import <UIKit/UIKit.h>

@interface MeshSecretPrompt : NSObject
+ (void)verifyFrom:(UIViewController *)from then:(void (^)(NSString *secret))next;
@end
