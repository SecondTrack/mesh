// Emojis auf aktuellem Stand (Noto, Unicode 18) unter iOS 6: Dessen Emoji-Schrift endet 2012, alles
// Neuere (🦆, 🥺, Hautfarben, Familien, Flaggen-Sequenzen …) bliebe leer. Die Bilder liegen gepackt in
// Resources/emoji.pack (tools/build-emoji.sh). install ersetzt das Zeichnen von UILabel, sobald ein Text
// Emojis enthält (nicht in Fenstern von UIKit wie der Tastatur); Texte ohne Emoji laufen unverändert über
// UIKit. Wo die Größe zählt (Blasen), misst textSize: mit denselben Maßen wie das Zeichnen.
// Erkennen und Setzen macht MeshEmojiText (ein Weg für Labels, Blasen und Felder); hier kommen Bilder,
// UIFont und der Satz-Speicher dazu. Messen und Zeichnen nutzen dieselbe MeshEmojiLayout.
#import <UIKit/UIKit.h>
#import "MeshEmojiText.h"

@interface MeshEmoji : NSObject
+ (void)install;                                  // einmal beim Start
+ (BOOL)containsEmoji:(NSString *)text;
+ (UIImage *)imageForKey:(NSString *)key;         // "1f986", "1f468_200d_1f469", "frosch_kuss" …; nil wenn unbekannt
+ (NSArray *)keysIn:(NSString *)text;             // Schlüssel der Emojis im Text (Tests)
+ (NSArray *)allKeys;                              // alle Schlüssel im Pack (Tastatur; ohne eigene Emojis)
// Wie sizeWithFont:constrainedToSize:lineBreakMode:, mit Emojis in ihrer gezeichneten Größe.
+ (CGSize)textSize:(NSString *)text font:(UIFont *)font constrainedTo:(CGSize)size;
+ (CGSize)sizeOf:(NSString *)text font:(UIFont *)font constrainedTo:(CGSize)size lines:(NSInteger)lines;
// Breite einer Zeile mit Leerzeichen am Ende (Einfügemarke der Chat-Eingabe), wie draw: sie setzt.
+ (CGFloat)lineWidth:(NSString *)text font:(UIFont *)font;
+ (void)draw:(NSString *)text font:(UIFont *)font color:(UIColor *)color alignment:(NSTextAlignment)alignment
       lines:(NSInteger)lines inRect:(CGRect)rect;
// Satz für Text, Schrift und Fläche (zwischengespeichert); width CGFLOAT_MAX = eine Zeile ohne Umbruch.
+ (MeshEmojiLayout *)layoutFor:(NSString *)text font:(UIFont *)font width:(CGFloat)width height:(CGFloat)height lines:(NSInteger)lines;
+ (void)drawLayout:(MeshEmojiLayout *)layout color:(UIColor *)color alignment:(NSTextAlignment)alignment inRect:(CGRect)rect;
+ (void)setPackDirectory:(NSString *)dir;         // Tests (sonst das App-Bundle)
@end
