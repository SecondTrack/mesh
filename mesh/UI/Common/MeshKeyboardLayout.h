// Reine Logik der eigenen Tastatur (ohne UIKit, auf dem Mac getestet): Tastenbelegung je Seite und
// Sprache, Umlaute auf langem Druck, automatische Großschreibung, was ⌫ löscht, und die Emoji-Liste
// (Kategorien, Schlüssel -> Text). Zeichnen und Eingabe macht MeshKeyboard.
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

typedef NS_ENUM(NSInteger, MeshKeyKind) {
    MeshKeyChar,       // fügt text ein
    MeshKeyShift,
    MeshKeyDelete,
    MeshKeyNumbers,    // "123": Ziffern und Zeichen
    MeshKeyLetters,    // "ABC"
    MeshKeySymbols,    // "#+=": zweite Zeichenseite
    MeshKeyGlobe,      // Sprache wechseln
    MeshKeyEmoji,
    MeshKeySpace,
    MeshKeyReturn,
};

typedef NS_ENUM(NSInteger, MeshKeyPage) {
    MeshKeyPageLetters,
    MeshKeyPageNumbers,
    MeshKeyPageSymbols,
    MeshKeyPagePad,         // Ziffernblock (Zahlenfelder, PIN)
    MeshKeyPageDecimalPad,  // Ziffernblock mit Dezimalzeichen
    MeshKeyPagePhonePad,    // Ziffernblock mit "+"
};

// Wie UITextAutocapitalizationType (gleiche Werte).
typedef NS_ENUM(NSInteger, MeshAutoCap) {
    MeshAutoCapNone, MeshAutoCapWords, MeshAutoCapSentences, MeshAutoCapAll,
};

typedef NS_ENUM(NSInteger, MeshEmojiGroup) {
    MeshEmojiSmileys, MeshEmojiNature, MeshEmojiFood, MeshEmojiActivities,
    MeshEmojiTravel, MeshEmojiObjects, MeshEmojiSymbols, MeshEmojiFlags,
    MeshEmojiGroupCount,
};

@interface MeshKeySpec : NSObject
@property (nonatomic) MeshKeyKind kind;
@property (nonatomic, copy) NSString *text;   // Zeichen (Buchstaben klein) bzw. Beschriftung ("123", "ABC", "#+=")
@property (nonatomic) CGRect frame;           // sichtbare Taste
@property (nonatomic) CGRect hitFrame;        // Trefferfläche: lückenlos bis zu den Nachbarn
@end

@interface MeshKeyboardLayout : NSObject

// Tasten einer Seite für die Sprache ("de" QWERTZ, sonst QWERTY) in einer Fläche der Größe size.
// decimal: Dezimalzeichen für MeshKeyPageDecimalPad.
+ (NSArray *)keysForPage:(MeshKeyPage)page language:(NSString *)lang size:(CGSize)size decimal:(NSString *)decimal;
// Varianten auf langem Druck (Umlaute, Akzente, ß, Anführungszeichen …); nil wenn keine.
+ (NSArray *)variantsFor:(NSString *)ch language:(NSString *)lang;
// Soll das nächste Zeichen groß sein? before = Text vor der Einfügemarke.
+ (BOOL)shouldCapitalizeAfter:(NSString *)before mode:(MeshAutoCap)mode;
// Was ⌫ an der Stelle cursor löscht: das ganze zusammengesetzte Zeichen davor (Emoji mit ZWJ,
// Hautfarbe, Flaggenpaar, Tastenkappe, Tag-Folge, Akzent-Kombination, CRLF).
+ (NSRange)deleteRangeIn:(NSString *)text cursor:(NSUInteger)cursor;

// Emojis
+ (NSArray *)codepointsForEmojiKey:(NSString *)key;          // "1f468_200d_1f469" -> @[0x1F468, 0x200D, 0x1F469]
+ (NSString *)stringForEmojiKey:(NSString *)key;              // gültiger Unicode-Text, mit FE0F wo nötig
+ (BOOL)isHiddenEmojiKey:(NSString *)key;                     // Hautfarben, nackte Ziffern, einzelne Regionalbuchstaben
+ (MeshEmojiGroup)groupForEmojiKey:(NSString *)key;
// Alle sichtbaren Schlüssel nach Gruppe (MeshEmojiGroupCount Arrays), je Gruppe nach Codepunkten sortiert.
+ (NSArray *)groupEmojiKeys:(NSArray *)keys;

@end
