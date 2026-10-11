// Menü "⋯" im Chat-Kopf: Selbstlöschen (Dauer, dann Start der Uhr) und Chat leeren, wie Android.
#import <Foundation/Foundation.h>

@interface MeshChatMenu : NSObject
+ (void)showForPeer:(NSString *)peerHex changed:(void (^)(void))changed;   // changed: Timer neu gesetzt
@end
