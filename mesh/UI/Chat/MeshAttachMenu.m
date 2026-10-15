#import "MeshAttachMenu.h"
#import "MeshSession.h"
#import "MeshCaps.h"
#import "MeshPopup.h"
#import "MeshImagePicker.h"
#import "MeshImageCodec.h"
#import "MeshVideoCodec.h"
#import "ContactPickerViewController.h"
#import "MeshImageSendPreview.h"
#import "MeshL10n.h"

static const NSTimeInterval kMaxVideoSeconds = 20;   // passt bei niedriger Qualität in eine Nachricht

@implementation MeshAttachMenu

+ (void)showFrom:(UIViewController *)host peer:(NSString *)peer replyTo:(NSString *(^)(void))replyTo sent:(void (^)(void))sent {
    BOOL camera = [MeshCaps hasCamera];
    NSArray *titles = camera ? @[L(@"Camera"), L(@"Photo from library"), L(@"Video"), L(@"Share contact")]
                             : @[L(@"Photo from library"), L(@"Video"), L(@"Share contact")];
    [MeshPopup sheet:nil options:titles destructiveIndex:-1 handler:^(NSInteger idx) {
        if (idx < 0) return;
        if (!camera) idx++;
        if (idx == 0) [self pickImageFrom:host source:UIImagePickerControllerSourceTypeCamera peer:peer replyTo:replyTo sent:sent];
        if (idx == 1) [self pickImageFrom:host source:UIImagePickerControllerSourceTypePhotoLibrary peer:peer replyTo:replyTo sent:sent];
        if (idx == 2) [self pickVideoFrom:host peer:peer replyTo:replyTo sent:sent];
        if (idx == 3) [self shareContactFrom:host peer:peer sent:sent];
    }];
}

+ (void)pickImageFrom:(UIViewController *)host source:(UIImagePickerControllerSourceType)source peer:(NSString *)peer
              replyTo:(NSString *(^)(void))replyTo sent:(void (^)(void))sent {
    // Erst die Vorschau (wie Android), gesendet wird das dort gezeigte JPEG. Kurz warten, bis die
    // Auswahl zu ist: iOS 5/6 schieben sonst keine Seite nach.
    [MeshImagePicker pickFrom:host source:source done:^(UIImage *image) {
        NSData *jpeg = [MeshImageCodec jpegForChat:image];
        if (!jpeg.length) return;
        MeshImageSendPreview *preview = [[MeshImageSendPreview alloc] initWithJPEG:jpeg send:^(NSData *data) {
            if ([[MeshSession shared] sendImageTo:peer jpeg:data replyTo:replyTo()] && sent) sent();
        }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [host.navigationController pushViewController:preview animated:YES];
        });
    }];
}

+ (void)pickVideoFrom:(UIViewController *)host peer:(NSString *)peer replyTo:(NSString *(^)(void))replyTo sent:(void (^)(void))sent {
    UIImagePickerControllerSourceType source = [MeshCaps hasCamera] ? UIImagePickerControllerSourceTypeCamera : UIImagePickerControllerSourceTypePhotoLibrary;
    [MeshImagePicker pickVideoFrom:host source:source maxSeconds:kMaxVideoSeconds done:^(NSURL *movie) {
        [MeshVideoCodec mp4FromMovie:movie maxBytes:MeshMaxFileBytes done:^(NSData *mp4) {
            if (!mp4) { [MeshPopup info:L(@"Video too long to send")]; return; }
            if ([[MeshSession shared] sendFileTo:peer data:mp4 name:@"video.mp4" mime:@"video/mp4" replyTo:replyTo()] && sent) sent();
        }];
    }];
}

// Eigene Seite wie bei Android statt einer Liste im Popup.
+ (void)shareContactFrom:(UIViewController *)host peer:(NSString *)peer sent:(void (^)(void))sent {
    [host.navigationController pushViewController:[[ContactPickerViewController alloc] initWithPeer:peer sent:sent] animated:YES];
}

@end
