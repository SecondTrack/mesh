// Eine Konversation: Bubbles + Eingabeleiste im Mesh-Design.
#import <UIKit/UIKit.h>

@interface ChatViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>
- (instancetype)initWithPeer:(NSString *)peerHex;
@end
