// Bild oder Video aus Kamera oder Mediathek holen. Gibt es die Kamera nicht, wird die
// Mediathek geöffnet. Hält sich selbst am Leben, bis der Picker fertig ist.
#import <UIKit/UIKit.h>

@interface MeshImagePicker : NSObject
+ (void)pickFrom:(UIViewController *)host source:(UIImagePickerControllerSourceType)source done:(void (^)(UIImage *image))done;
// Video in niedriger Qualität. Die Datei hinter movie liegt im tmp-Ordner: nach Gebrauch löschen.
+ (void)pickVideoFrom:(UIViewController *)host source:(UIImagePickerControllerSourceType)source
           maxSeconds:(NSTimeInterval)maxSeconds done:(void (^)(NSURL *movie))done;
@end
