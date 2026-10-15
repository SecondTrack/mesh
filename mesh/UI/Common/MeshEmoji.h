// Emojis auf aktuellem Stand (Noto, Unicode 18) unter iOS 6: Dessen Emoji-Schrift endet 2012, alles
// Neuere (🦆, 🥺, Hautfarben, Familien, Flaggen-Sequenzen …) bliebe leer. Die Bilder liegen gepackt in
// Resources/emoji.pack (tools/build-emoji.sh). install ersetzt das Zeichnen von UILabel, sobald ein Text
// Emojis enthält (nicht in Fenstern von UIKit wie der Tastatur); Texte ohne Emoji laufen unverändert über
// UIKit. Wo die Größe zählt (Blasen), misst textSize: mit denselben Maßen wie das Zeichnen.
// Gezeichnet wird mit CoreText: jedes Emoji ist ein Platzhalter (U+FFFC, CTRunDelegate) in Emoji-
// Größe, darüber kommt das Bild. Messen und Zeichnen brechen Zeilen gleich um.
#import <UIKit/UIKit.h>

@interface MeshEmoji : NSObject
+ (void)install;                                  // einmal beim Start
+ (BOOL)containsEmoji:(NSString *)text;
+ (UIImage *)imageForKey:(NSString *)key;         // "1f986", "1f468_200d_1f469" …; nil wenn unbekannt
+ (NSArray *)keysIn:(NSString *)text;             // Schlüssel der Emojis im Text (Tests)
+ (NSArray *)allKeys;                              // alle Schlüssel im Pack (Tastatur)
// Wie sizeWithFont:constrainedToSize:lineBreakMode:, mit Emojis in ihrer gezeichneten Größe.
+ (CGSize)textSize:(NSString *)text font:(UIFont *)font constrainedTo:(CGSize)size;
+ (CGSize)sizeOf:(NSString *)text font:(UIFont *)font constrainedTo:(CGSize)size lines:(NSInteger)lines;
+ (void)draw:(NSString *)text font:(UIFont *)font color:(UIColor *)color alignment:(NSTextAlignment)alignment
       lines:(NSInteger)lines inRect:(CGRect)rect;
+ (void)setPackDirectory:(NSString *)dir;         // Tests (sonst das App-Bundle)
@end
