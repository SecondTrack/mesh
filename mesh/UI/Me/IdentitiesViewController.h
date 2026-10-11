// Identitäten wie in der Android-App: erst nach erneuter PIN sichtbar (wer das entsperrte Gerät
// in die Hand bekommt, sieht nicht, dass es weitere gibt). Umschalten, neu anlegen, per nsec
// übernehmen, gemeinsamer Posteingang.
#import <UIKit/UIKit.h>

@interface IdentitiesViewController : UIViewController
- (instancetype)initWithSecret:(NSString *)secret;   // der eben bestätigte Code, fürs Anlegen
@end
