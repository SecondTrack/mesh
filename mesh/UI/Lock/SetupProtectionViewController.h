// Erster Start: Schutzart wählen. Drei Karten mit Zahlen (wie lange ein Angreifer bräuchte, der das
// Gerät ausgelesen hat): 6-stellige PIN, 5 Wörter (empfohlen), 6 Wörter (am sichersten).
#import <UIKit/UIKit.h>
#import "MeshSession.h"

@interface SetupProtectionViewController : UIViewController
@property (nonatomic, copy) NSString *pageTitle;   // gesetzt = Unterseite (Schutz ändern) mit Kopfzeile und Zurück
@property (nonatomic, copy) void (^onChoose)(MeshSecretKind kind, NSUInteger words);   // words = 0 bei der PIN
@end
