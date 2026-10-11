// Textdatei im Vollbild lesen (nur Anzeige, ohne Links oder Datenerkennung). Schließen oben links.
#import <UIKit/UIKit.h>

@interface MeshTextViewer : UIViewController
- (instancetype)initWithTitle:(NSString *)title text:(NSString *)text;
@end
