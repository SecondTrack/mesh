#import "MeshImageViewer.h"

@implementation MeshImageViewer {
    UIImage *_image;
}
- (instancetype)initWithImage:(UIImage *)image { if ((self = [super init])) _image = image; return self; }

- (void)loadView {
    [self mesh_useFullScreenLayout];
    self.view = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.view.backgroundColor = [UIColor blackColor];
    UIImageView *iv = [[UIImageView alloc] initWithFrame:self.view.bounds];
    iv.contentMode = UIViewContentModeScaleAspectFit; iv.image = _image;
    [self.view addSubview:iv];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(close)];
    [self.view addGestureRecognizer:tap];
}
- (void)close { [self mesh_dismissAnimated:YES]; }
@end
