// Sperrbildschirm für die Passphrase: Wörter über die Tastatur, Prüfung mit scrypt (dauert etwa
// eine Sekunde), Sperrzeit nach Fehlversuchen wie bei der PIN.
#import <UIKit/UIKit.h>

@interface PassphraseLockViewController : UIViewController <UITextFieldDelegate>
@property (nonatomic, copy) void (^onUnlocked)(void);
@property (nonatomic, copy) void (^onStartOver)(void);   // nach Zurücksetzen oder Panik-Code: Einrichtung
@property (nonatomic, assign) BOOL verifyMode;       // Wörter bestätigen (Sicherheit, Identitäten): wie der Sperrbildschirm
@property (nonatomic, copy) void (^onVerified)(NSString *words);
@property (nonatomic, copy) void (^onCancel)(void);  // "Abbrechen" statt "Wörter vergessen?"
@end
