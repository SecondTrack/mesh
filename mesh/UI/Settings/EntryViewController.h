// Einstellungsseite für einen geheimen Wert (Notlöschungs-Codewort, Panik-Code): Erklärung, Feld
// (auf Wunsch mit Wiederholung), Speichern und optional Entfernen. Ohne Feld (fieldless) ist es
// eine Erklärseite, deren Knopf weiterführt (Panik-PIN mit Ziffernblock).
#import <UIKit/UIKit.h>

@interface EntryViewController : UIViewController <UITextFieldDelegate>
- (instancetype)initWithTitle:(NSString *)title text:(NSString *)text;
@property (nonatomic, copy) NSString *status;        // z.B. "Ist an", über der Erklärung
@property (nonatomic, copy) NSString *placeholder;
@property (nonatomic) BOOL secure;                   // verdeckt, ohne Autokorrektur
@property (nonatomic) BOOL repeat;                   // zweites Feld zur Kontrolle
@property (nonatomic) BOOL fieldless;
@property (nonatomic, copy) NSString *saveTitle;
@property (nonatomic, copy) NSString *removeTitle;   // nil = kein Entfernen-Knopf
// Fehlertext oder nil; bei nil führt der Aufrufer weiter (meist zurück zu Sicherheit).
@property (nonatomic, copy) NSString *(^onSave)(NSString *value);
@property (nonatomic, copy) void (^onRemove)(void);
@end
