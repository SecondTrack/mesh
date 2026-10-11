// Kontaktdetails: großer Avatar, Name, npub (kopieren), Verifizieren
// und Safety-Number.
#import <UIKit/UIKit.h>

@interface PeerProfileViewController : UIViewController
- (instancetype)initWithPeer:(NSString *)peerHex;
@end
