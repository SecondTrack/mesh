// Label für Text von Nutzern (Namen, Vorschauen, Beschreibungen, Systemzeilen mit Namen): Emojis als
// Noto-Bilder wie in den Blasen, samt Hautfarben und allem nach 2012, das UILabel unter iOS 6 nicht kennt.
// Unterklasse von UILabel, also dieselbe Schnittstelle (Schrift, Farbe, Ausrichtung, Zeilen); zu lang:
// "…" am Ende. Der Satz liegt je Text und Größe im Speicher von MeshEmoji, gleicher Text zeichnet nicht
// neu (Chatliste beim Scrollen). Texte ohne Emoji zeichnet UILabel selbst. Feste Texte bleiben UILabel.
#import <UIKit/UIKit.h>

@interface MeshEmojiLabel : UILabel
@end
