// Zeile in Einstellungslisten: Icon-Kachel, Titel, Untertitel, Pfeil, Trennlinie.
#import <UIKit/UIKit.h>

@interface MeshMenuRow : UIButton
+ (CGFloat)height;
+ (instancetype)rowAtY:(CGFloat)y width:(CGFloat)width icon:(NSString *)icon title:(NSString *)title subtitle:(NSString *)subtitle;
// Zeile anlegen, in host einhängen, Ziel setzen; liefert die y-Position für die nächste Zeile.
+ (CGFloat)addTo:(UIView *)host y:(CGFloat)y width:(CGFloat)width icon:(NSString *)icon title:(NSString *)title
        subtitle:(NSString *)subtitle target:(id)target action:(SEL)action;
@property (nonatomic, copy) NSString *detail;   // aktueller Wert rechts statt des Pfeils (Einstellungen)
@end
