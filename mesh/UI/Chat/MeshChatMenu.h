// Menü "⋯" im Chat-Kopf: Medien, Selbstlöschen (Dauer, dann Start der Uhr) und Chat leeren, wie Android.
#import <Foundation/Foundation.h>

@interface MeshChatMenu : NSObject
+ (void)showForPeer:(NSString *)peerHex media:(void (^)(void))media changed:(void (^)(void))changed;   // changed: Timer neu gesetzt
+ (void)chooseTimerFor:(NSString *)peerHex changed:(void (^)(void))changed;
@end
