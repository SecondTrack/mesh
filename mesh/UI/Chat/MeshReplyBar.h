// Leiste über der Eingabe, solange man auf eine Nachricht antwortet: wem, Anfang der Nachricht,
// Schließen-Knopf.
#import <UIKit/UIKit.h>

@interface MeshReplyBar : UIView
+ (CGFloat)height;
- (void)setAuthor:(NSString *)author text:(NSString *)text;
@property (nonatomic, readonly) UIButton *closeButton;
@end
