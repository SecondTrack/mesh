// Emojis im Text finden und Zeilen setzen, ohne UIKit (auf dem Mac getestet). Der eine Weg für alles,
// was Emojis zeigt: Blasen, Labels (MeshEmojiLabel und das eingehängte UILabel), Eingabefelder.
// Gemessen und gezeichnet wird dieselbe MeshEmojiLayout; die Einfügemarke steht an deren Breite.
//
// Erkennung: Folge (Basis, FE0F/FE0E, Hautfarbe, Tastenkappe, Tag-Folge, ZWJ-Verbindung) -> Schlüssel im
// Pack (Codepunkte ohne FE0F, wie die Noto-Dateinamen). Fehlt die volle Folge, zerfällt sie in Teile,
// die es gibt (ohne Hautfarbe, ohne Tags, ZWJ-Teile, Regionalbuchstaben). Was als Text bleibt, verliert
// unsichtbare Reste (FE0F, ZWJ, Tags), die die Schrift von iOS 6 als Kästchen zeigen würde.
// Eigene Emojis (":frosch_kuss:", MeshCustomEmoji) sind ein Teil mit dem Namen als Schlüssel.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreText/CoreText.h>

@interface MeshEmojiText : NSObject
+ (void)setPackDirectory:(NSString *)dir;          // Tests (sonst das App-Bundle)
+ (NSDictionary *)packIndex;                        // Schlüssel -> NSValue (NSRange in emoji.pack)
+ (NSString *)packPath;                             // emoji.pack
+ (NSArray *)allKeys;
// Teile: NSString = Text, NSArray = Schlüssel eines Emojis (meist einer).
+ (NSArray *)segmentsOf:(NSString *)text;
+ (BOOL)containsEmoji:(NSString *)text;            // mindestens ein Bild
+ (NSArray *)keysIn:(NSString *)text;
@end

// Gesetzter Text: Zeilen mit Platzhaltern (U+FFFC, CTRunDelegate) in Emoji-Größe. Unveränderlich,
// darf zwischengespeichert werden (MeshEmoji). Textfarbe kommt beim Zeichnen aus dem Kontext.
@interface MeshEmojiLayout : NSObject
// width: Umbruchbreite (CGFLOAT_MAX = eine Zeile). height: Platz nach unten (CGFLOAT_MAX = beliebig).
// lines: höchstens so viele Zeilen (0 = beliebig); die letzte sichtbare wird mit "…" gekürzt.
// lineHeight: Mindesthöhe einer Zeile (UIFont.lineHeight).
- (instancetype)initWithText:(NSString *)text font:(CTFontRef)font lineHeight:(CGFloat)lineHeight
                       width:(CGFloat)width height:(CGFloat)height lines:(NSInteger)lines;
@property (nonatomic, readonly) CGSize size;           // aufgerundet, ohne Leerzeichen am Zeilenende
@property (nonatomic, readonly) CGFloat lineWidth;     // erste Zeile samt Leerzeichen am Ende (Einfügemarke)
@property (nonatomic, readonly) NSUInteger lineCount;
@property (nonatomic, readonly) BOOL truncated;
@property (nonatomic, readonly) CGFloat emojiSize;
// Zeichnet in UIKit-Koordinaten (y nach unten), senkrecht in rect zentriert; Text in der Füllfarbe des
// Kontexts. emoji bekommt Schlüssel und Rahmen jedes Bildes (zeichnet es). ctx NULL: nur Rahmen melden.
- (void)drawInContext:(CGContextRef)ctx rect:(CGRect)rect alignment:(CTTextAlignment)alignment
                emoji:(void (^)(NSString *key, CGRect frame))emoji;
@end
