#import "MeshImageSendPreview.h"
#import "MeshScreen.h"
#import "MeshPageHeader.h"
#import "MeshControls.h"
#import "MeshTheme.h"
#import "MeshImageCodec.h"
#import "MeshFormat.h"
#import "MeshL10n.h"

@implementation MeshImageSendPreview {
    NSData *_jpeg;
    void (^_send)(NSData *);
}

- (instancetype)initWithJPEG:(NSData *)jpeg send:(void (^)(NSData *))send {
    if ((self = [super init])) { _jpeg = jpeg; _send = [send copy]; }
    return self;
}

- (void)loadView {
    [self mesh_loadScreen];
    CGFloat W = self.view.bounds.size.width, H = self.view.bounds.size.height;
    MeshPageHeader *header = [[MeshPageHeader alloc] initWithWidth:W title:L(@"Send photo") target:self back:@selector(mesh_goBack)];
    [self.view addSubview:header];
    CGFloat top = [MeshPageHeader height], buttons = 64;

    UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(12, top + 12, W - 24, H - top - buttons - 44)];
    iv.contentMode = UIViewContentModeScaleAspectFit;
    iv.image = [MeshImageCodec imageFromData:_jpeg formats:MeshImageJPEG];   // genau das, was rausgeht
    [self.view addSubview:iv];

    UILabel *size = [MeshControls labelWithFrame:CGRectMake(12, H - buttons - 30, W - 24, 20) font:[MeshTheme timeFont] color:[MeshTheme muted]];
    size.textAlignment = NSTextAlignmentCenter;
    CGSize px = iv.image.size;
    size.text = [NSString stringWithFormat:@"%.0f × %.0f · %@", px.width, px.height,
                 [MeshFormat fileDetail:@"" mime:@"image/jpeg" bytes:(long long)_jpeg.length]];
    [self.view addSubview:size];

    CGFloat bw = (W - 3 * 16) / 2, by = H - buttons + 6;
    [self.view addSubview:[MeshControls secondaryButtonWithFrame:CGRectMake(16, by, bw, 44) title:L(@"Cancel") target:self action:@selector(mesh_goBack)]];
    [self.view addSubview:[MeshControls primaryButtonWithFrame:CGRectMake(32 + bw, by, bw, 44) title:L(@"Send") target:self action:@selector(sendTapped)]];
}

- (void)sendTapped {
    void (^send)(NSData *) = _send;
    _send = nil;   // kein zweites Senden bei Doppeltippen
    if (send) send(_jpeg);
    [self.navigationController popViewControllerAnimated:YES];
}

@end
