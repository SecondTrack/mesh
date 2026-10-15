// Eine Konversation: Bubbles + Eingabeleiste im Mesh-Design.
#import <UIKit/UIKit.h>

@interface ChatViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
- (instancetype)initWithPeer:(NSString *)peerHex;
// Gruppenchat löschen mit Rückfrage. Admin einer aktiven Gruppe: eigener Dialog, denn das löst die
// Gruppe für alle auf (B8.8). done nach dem Löschen (nil = nichts).
+ (void)confirmDeleteGroup:(NSString *)chat done:(void (^)(void))done;
@end
