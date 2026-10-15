// Wiederkehrende Bedienelemente im Mesh-Look.
#import <UIKit/UIKit.h>
#import "MeshEmojiField.h"

@interface MeshControls : NSObject
// Eingabefeld (UITextField) für Schlüssel, Codes und Geheimnisse. mono: Festbreitenschrift, ohne
// Großschreibung und Autokorrektur. Freien Text (Namen, Beschreibungen) nimmt textFieldWithFrame:,
// sonst erscheinen neuere Emojis beim Tippen als Kästchen.
+ (UITextField *)fieldWithFrame:(CGRect)frame placeholder:(NSString *)placeholder mono:(BOOL)mono delegate:(id<UITextFieldDelegate>)delegate;
// Gleiches Feld für freien Text (Wortanfänge groß), zeichnet Emojis wie die Blasen.
+ (MeshEmojiField *)textFieldWithFrame:(CGRect)frame placeholder:(NSString *)placeholder delegate:(id<MeshEmojiFieldDelegate>)delegate;
// Hauptknopf: Akzentfläche, dunkle Schrift.
+ (UIButton *)primaryButtonWithFrame:(CGRect)frame title:(NSString *)title target:(id)target action:(SEL)action;
// Nebenknopf: erhöhte Fläche mit feinem Rahmen, helle Schrift.
+ (UIButton *)secondaryButtonWithFrame:(CGRect)frame title:(NSString *)title target:(id)target action:(SEL)action;
// Kleine Überschrift über einem Abschnitt (in Großbuchstaben übergeben).
// Symbol links vom Titel (eigene Glyphen statt Emoji/Unicode-Zeichen im Text)
+ (void)setIcon:(UIImage *)icon onButton:(UIButton *)button;

+ (UILabel *)sectionLabelWithFrame:(CGRect)frame text:(NSString *)text;
// Text auf transparentem Grund.
+ (UILabel *)labelWithFrame:(CGRect)frame font:(UIFont *)font color:(UIColor *)color;
// Dasselbe für Text von Nutzern (Namen, Beschreibungen): Emojis als Bilder (MeshEmojiLabel).
+ (UILabel *)userLabelWithFrame:(CGRect)frame font:(UIFont *)font color:(UIColor *)color;
// Karte: erhöhte Fläche mit Kartenradius.
+ (UIView *)cardWithFrame:(CGRect)frame;
// Karte mit Titel, Untertitel und Schalter rechts (Höhe 64); der Schalter meldet ValueChanged an target.
+ (UIView *)switchCardWithFrame:(CGRect)frame title:(NSString *)title subtitle:(NSString *)subtitle
                             on:(BOOL)on target:(id)target action:(SEL)action;
@end
