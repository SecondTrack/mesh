// Text der Mesh-Eingabefelder (MeshEmojiField) ohne UIKit (auf dem Mac getestet): eine Zeile,
// Einfügemarke immer am Ende, optional alles ausgewählt. ⌫ löscht ganze Zeichen wie die Tastatur
// (Emoji mit ZWJ, Hautfarbe, Flagge).
#import <Foundation/Foundation.h>

@interface MeshLineText : NSObject
@property (nonatomic, copy) NSString *text;      // Setter macht einzeilig, nie nil
@property (nonatomic) BOOL allSelected;           // nur bei Text; Tippen ersetzt, ⌫ leert
@property (nonatomic, readonly) NSRange selectedRange;   // Ende oder alles
// Wie textField:shouldChangeCharactersInRange:replacementString: vor jeder Änderung durch Tippen,
// ⌫ oder Einfügen (nicht beim Setzen von text): Bereich in UTF-16 des bisherigen Texts, Ersatz schon
// bereinigt und gekürzt. NO verwirft die Änderung (der Block darf text selbst setzen).
@property (nonatomic, copy) BOOL (^shouldChange)(NSRange range, NSString *replacement);
- (BOOL)insert:(NSString *)s;                     // YES = Text geändert
- (BOOL)deleteBackward;
- (BOOL)paste:(NSString *)raw;                    // bereinigt (pasteText:), ersetzt eine Auswahl
// Zeilenumbrüche und Tabs zu Leerzeichen
+ (NSString *)singleLine:(NSString *)raw;
// Eingefügter Text: Steuer- und Schreibrichtungszeichen raus (ZWJ bleibt für Emojis), einzeilig, gekürzt
+ (NSString *)pasteText:(NSString *)raw max:(NSUInteger)max;
+ (NSUInteger)maxLength;                          // Obergrenze des Feldes (UTF-16)
@end
