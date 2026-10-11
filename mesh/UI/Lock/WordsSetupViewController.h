// Passphrase festlegen: Die App würfelt die Wörter und zeigt sie nummeriert (auf Papier
// abschreiben, auf Wunsch neu würfeln), dann werden sie zur Kontrolle eingetippt.
#import <UIKit/UIKit.h>
#import "MeshSession.h"

@interface WordsSetupViewController : UIViewController <UITextFieldDelegate>
- (instancetype)initWithWords:(NSUInteger)count;
// Mit den bestätigten Wörtern aufgerufen (scrypt dauert, davor steht "Verschlüssele …"). Bei
// MeshPinOK geht der Aufrufer weiter, sonst zeigt der Bildschirm den Fehler.
@property (nonatomic, copy) MeshPinResult (^onConfirmed)(NSString *phrase);
@property (nonatomic, copy) void (^onBack)(void);   // nil = eine Seite zurück
@end
