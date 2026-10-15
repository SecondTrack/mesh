// Gruppenprofil (Kopfzeile im Gruppenchat antippen): Name, Mitglieder (Admin markiert, beim Admin
// auch die noch Eingeladenen), Medien; der Admin kann umbenennen, Selbstlöschen stellen, Mitglieder
// hinzufügen und entfernen. Alle können verlassen (Admin: Gruppe auflösen).
#import <UIKit/UIKit.h>

@interface GroupProfileViewController : UIViewController
- (instancetype)initWithChat:(NSString *)chat;   // "g:<gid>"
@end
