// Eigene Tastatur für alle Eingabefelder von Mesh (inputView statt der iOS-Tastatur).
// Grund: die iOS-Tastatur lernt Wörter und legt sie unverschlüsselt im Wörterbuch-Cache ab. Diese hier
// merkt sich nichts Getipptes (nur die gewählte Belegung de/en), liest nie die Zwischenablage und zeigt
// in sicheren Feldern keine Tasten-Vorschau.
//
// Belegung QWERTZ/QWERTY (🌐 wechselt), Ziffern- und Zeichenseiten, Ziffernblock für Zahlenfelder,
// Umschalt (einmal tippen = ein Großbuchstabe, zweimal = feststellen, automatisch nach Feldeinstellung),
// Umlaute/ß auf langem Druck, Emoji-Seiten mit allem, was Mesh zeichnen kann.
// Höhe 216 wie die iOS-Tastatur hochkant: UIKit meldet sie mit den üblichen Tastatur-Notifications, das
// Ausweichen der Seiten (MeshScreen, Chat) bleibt unverändert.
#import <UIKit/UIKit.h>

// Eigene Eingabefelder ohne UITextInput (MeshEmojiField): Einfügemarke immer am Ende,
// deleteBackward löscht selbst ganze Emojis. Beginn und Ende melden sie mit den Notifications unten.
@protocol MeshKeyTarget <UIKeyInput>
@property (nonatomic, readonly, copy) NSString *text;
@property (nonatomic, readonly) NSRange selectedRange;   // Ende oder alles
- (void)returnPressed;
@end
extern NSString *const MeshKeyTargetDidBeginEditingNotification;
extern NSString *const MeshKeyTargetDidEndEditingNotification;

@interface MeshKeyboard : UIView <UIInputViewAudioFeedback>
// Die Mesh-Tastatur für ein UITextField, UITextView oder MeshKeyTarget (setzt dessen inputView; eine gemeinsame Tastatur).
+ (void)attachTo:(UIResponder<UIKeyInput> *)field;
@end
