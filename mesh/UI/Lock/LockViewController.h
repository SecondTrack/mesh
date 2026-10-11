// PIN-Gate: Code festlegen (erstes Mal) oder eingeben (entsperren).
#import <UIKit/UIKit.h>
#import "MeshSession.h"

@interface LockViewController : UIViewController <UITextFieldDelegate>
@property (nonatomic, assign) BOOL setupMode;         // YES = Code festlegen
@property (nonatomic, assign) BOOL verifyMode;        // YES = Code bestätigen (Sicherheit, Identitäten): wie der Sperrbildschirm
@property (nonatomic, copy)   void (^onVerified)(NSString *pin);
@property (nonatomic, copy)   void (^onCancel)(void);     // "Abbrechen" statt "PIN vergessen?"
@property (nonatomic, copy)   NSString *chooseTitle;  // Titel beim Festlegen statt "PIN festlegen"/"Neue PIN"
@property (nonatomic, copy)   NSString *pageTitle;    // gesetzt = Unterseite mit Kopfzeile und Zurück statt Schild
// Festlegen ohne Einrichtung (neue PIN unter Sicherheit): bekommt die bestätigte PIN.
@property (nonatomic, copy)   MeshPinResult (^onPinChosen)(NSString *pin);
@property (nonatomic, copy)   void (^onUnlocked)(void);
@property (nonatomic, copy)   void (^onBack)(void);        // Festlegen: zurück zur Wahl der Schutzart
@property (nonatomic, copy)   void (^onStartOver)(void);   // nach Zurücksetzen/Panik-PIN: zur Einrichtung
@end
