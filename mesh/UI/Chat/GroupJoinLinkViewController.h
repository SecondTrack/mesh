// Beitreten per Link (B10): Gruppe (Name aus der Karte, sonst "Gruppe"), Admin "Name ~abcd" und der Hinweis,
// dass alle Mitglieder die eigene Mesh-ID sehen und jeder mit dem Link beitreten kann. Beitreten legt den
// Eintrag "tritt bei" an und schickt gj mit k an den Admin; Abbrechen schickt nichts.
#import <UIKit/UIKit.h>

@interface GroupJoinLinkViewController : UIViewController
- (instancetype)initWithLink:(NSString *)link groupName:(NSString *)name;   // name nil/leer = "Gruppe"
// Text als Link erkennen und die Seite zeigen; NO, wenn es kein Gruppen-Link ist.
+ (BOOL)openIfLink:(NSString *)text name:(NSString *)name from:(UINavigationController *)nav;
@end
