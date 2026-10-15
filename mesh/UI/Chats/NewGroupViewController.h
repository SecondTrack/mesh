// "Neue Gruppe": angenommene Kontakte wählen (höchstens 19), dann den Namen; die Einladungen gehen
// sofort hinaus. Dieselbe Seite fügt einer bestehenden Gruppe Mitglieder hinzu (nur Admin).
#import <UIKit/UIKit.h>

@interface NewGroupViewController : UIViewController
- (instancetype)initAddingToGroup:(NSString *)chat;   // nil = neue Gruppe
@end
