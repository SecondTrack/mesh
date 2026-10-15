// Einzeiliges Eingabefeld, das Emojis wie die Blasen zeichnet (Noto aus MeshEmoji): Das UITextField von
// iOS 6 kennt nur die Emoji-Schrift von 2012 und zeigt Neueres beim Tippen als Kästchen.
// Für alle Felder mit freiem Text (Chat, Namen, Suche, Popup-Eingabe); geheime Felder (PIN, Wörter)
// und Schlüssel-/Code-Felder bleiben UITextField.
// Nur für die Mesh-Tastatur (MeshKeyTarget): Einfügemarke immer am Ende, Text läuft nach links weg.
// Langes Drücken: Einfügen, Kopieren, Alles auswählen. Die Zwischenablage wird nur beim Einfügen gelesen.
// Verhält sich für den Aufrufer wie die genutzte Teilmenge von UITextField: Änderungen durch Tippen
// melden UIControlEventEditingChanged, Beginn/Ende EditingDidBegin/EditingDidEnd, der Delegate wird
// wie UITextFieldDelegate gefragt (Bereiche in UTF-16 des bisherigen Texts).
#import <UIKit/UIKit.h>
#import "MeshKeyboard.h"

@class MeshEmojiField;

@protocol MeshEmojiFieldDelegate <NSObject>
@optional
- (BOOL)emojiFieldShouldBeginEditing:(MeshEmojiField *)field;
- (void)emojiFieldDidBeginEditing:(MeshEmojiField *)field;
// Vor jeder Änderung durch Tippen, ⌫ oder Einfügen; NO verwirft sie (darf field.text selbst setzen).
- (BOOL)emojiField:(MeshEmojiField *)field shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string;
- (void)emojiFieldReturned:(MeshEmojiField *)field;     // Return-Taste; fügt nie eine Zeile ein
- (BOOL)emojiFieldShouldClear:(MeshEmojiField *)field;  // Löschknopf; NO = der Delegate erledigt es selbst
- (void)emojiFieldDidEndEditing:(MeshEmojiField *)field;
@end

@interface MeshEmojiField : UIControl <MeshKeyTarget, UITextInputTraits, UIGestureRecognizerDelegate>
@property (nonatomic, mesh_weak) id<MeshEmojiFieldDelegate> delegate;
@property (nonatomic, copy) NSString *text;         // nie nil; einzeilig
@property (nonatomic, copy) NSString *placeholder;
@property (nonatomic, strong) UIFont *font;
@property (nonatomic, strong) UIColor *textColor;
@property (nonatomic) NSTextAlignment textAlignment;   // links (Standard) oder Mitte; zu lang: läuft nach links weg
@property (nonatomic) CGFloat leftPadding;             // statt leftView
@property (nonatomic) UITextFieldViewMode clearButtonMode;   // Löschknopf rechts wie bei UITextField
@property (readwrite, strong) UIView *inputView;
// UITextInputTraits, die die Tastatur liest
@property (nonatomic) UITextAutocapitalizationType autocapitalizationType;
@property (nonatomic) UITextAutocorrectionType autocorrectionType;   // nur gespeichert (Mesh-Tastatur korrigiert nie)
@property (nonatomic) UIReturnKeyType returnKeyType;
@property (nonatomic) UIKeyboardType keyboardType;
@end
