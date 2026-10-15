// Eigene Emojis (Frosch-Set, docs/TEAM_GROUPS_PROTOCOL.md Teil C): keine Unicode-Zeichen, sondern Codes
// ":<name>:" im Text, <name> aus der festen Liste. Der Schlüssel eines eigenen Emojis ist sein Name
// ("frosch_kuss"); Noto-Schlüssel sind Hex mit "_" und können nie so heißen. Bilder: Resources/frosch/.
// Ohne UIKit (auf dem Mac getestet); Erkennen (MeshEmojiText) und Löschen (MeshKeyboardLayout) nutzen
// denselben Lauf von links, damit ⌫ genau das löscht, was als Bild erscheint.
#import <Foundation/Foundation.h>

@interface MeshCustomEmoji : NSObject
+ (NSArray *)names;                                // Liste v1, Reihenfolge der Tastatur
+ (BOOL)isName:(NSString *)key;
+ (NSString *)codeForName:(NSString *)name;        // "frosch_kuss" -> ":frosch_kuss:"
// Länge des bekannten Codes, der bei i beginnt (0 = keiner); name bekommt den Namen.
+ (NSUInteger)codeAt:(const unichar *)b length:(NSUInteger)n index:(NSUInteger)i name:(NSString **)name;
// Bereich des Codes, der genau bei end endet (von links gelesen wie die Anzeige); NSNotFound = keiner.
+ (NSRange)codeEndingIn:(NSString *)text at:(NSUInteger)end;
@end
