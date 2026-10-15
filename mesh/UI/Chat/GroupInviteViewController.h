// Offene Einladung in eine Gruppe: Name, Admin, Mitglieder und der Hinweis, dass alle Mitglieder
// die eigene Mesh-ID sehen; Annehmen öffnet den Gruppenchat, Ablehnen schickt nichts.
#import <UIKit/UIKit.h>

@interface GroupInviteViewController : UIViewController
- (instancetype)initWithChat:(NSString *)chat;   // "g:<gid>"
@end
