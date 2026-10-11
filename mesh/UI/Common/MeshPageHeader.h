// Kopfzeile von Unterseiten: Zurück-Pfeil, Titel, Trennlinie.
#import <UIKit/UIKit.h>

@interface MeshPageHeader : UIView
+ (CGFloat)height;   // inklusive MeshTheme topInset
- (instancetype)initWithWidth:(CGFloat)width title:(NSString *)title target:(id)target back:(SEL)back;
- (instancetype)initWithWidth:(CGFloat)width height:(CGFloat)height target:(id)target back:(SEL)back;   // eigener Inhalt
@property (nonatomic, readonly) UILabel *titleLabel;
@end

// Standardziel für den Zurück-Pfeil: Tastatur schließen, eine Seite zurück.
// Aufräumen beim Verlassen gehört in viewWillDisappear, dann greift es auf jedem Weg.
@interface UIViewController (MeshBack)
- (void)mesh_goBack;
// Unterseite: Kopfzeile mit Titel und Zurück, darunter eine Scroll-Fläche bis zum unteren Rand.
- (UIScrollView *)mesh_addPageTitled:(NSString *)title;
@end
