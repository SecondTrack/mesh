#import "MeshImagePicker.h"
#import "MeshCompat.h"
#import "MeshNotifications.h"

@interface MeshImagePicker () <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@end

static NSString *const kMovieType = @"public.movie";   // kUTTypeMovie, ohne MobileCoreServices

static MeshImagePicker *gActive;   // der Picker hält seinen Delegate nicht fest

@implementation MeshImagePicker {
    UIViewController *_host;
    UIImagePickerController *_picker;
    void (^_done)(id);             // UIImage oder NSURL
}

+ (MeshImagePicker *)startFrom:(UIViewController *)host source:(UIImagePickerControllerSourceType)source done:(void (^)(id))done {
    if (![UIImagePickerController isSourceTypeAvailable:source]) source = UIImagePickerControllerSourceTypePhotoLibrary;
    if (![UIImagePickerController isSourceTypeAvailable:source]) return nil;
    MeshImagePicker *p = [[MeshImagePicker alloc] init];
    p->_host = host;
    p->_done = [done copy];
    p->_picker = [[UIImagePickerController alloc] init];
    p->_picker.sourceType = source;
    p->_picker.delegate = p;
    gActive = p;
    // Beim Sperren schließt AppDelegate den Picker ohne Rückruf: dann hier loslassen, sonst hielte
    // gActive den Chat samt entschlüsselten Nachrichten bis zum nächsten Bild fest.
    [[NSNotificationCenter defaultCenter] addObserver:p selector:@selector(releaseForLock)
                                                 name:MeshWillLockNotification object:nil];
    return p;
}

+ (void)pickFrom:(UIViewController *)host source:(UIImagePickerControllerSourceType)source done:(void (^)(UIImage *))done {
    MeshImagePicker *p = [self startFrom:host source:source done:^(id result) {
        if ([result isKindOfClass:[UIImage class]]) done(result);
    }];
    if (p) [host mesh_present:p->_picker animated:YES];
}

+ (void)pickVideoFrom:(UIViewController *)host source:(UIImagePickerControllerSourceType)source
           maxSeconds:(NSTimeInterval)maxSeconds done:(void (^)(NSURL *))done {
    MeshImagePicker *p = [self startFrom:host source:source done:^(id result) {
        if ([result isKindOfClass:[NSURL class]]) done(result);
    }];
    if (!p) return;
    NSArray *types = [UIImagePickerController availableMediaTypesForSourceType:p->_picker.sourceType];
    if (![types containsObject:kMovieType]) { [p releaseForLock]; return; }
    p->_picker.mediaTypes = @[kMovieType];
    p->_picker.videoQuality = UIImagePickerControllerQualityTypeLow;
    p->_picker.videoMaximumDuration = maxSeconds;
    [host mesh_present:p->_picker animated:YES];
}

- (void)finish:(id)result {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _picker.delegate = nil;
    [_host mesh_dismissPresentedAnimated:YES];
    if (result && _done) _done(result);
    gActive = nil;
}

- (void)releaseForLock {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _picker.delegate = nil;
    _host = nil;
    _done = nil;
    gActive = nil;
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    [self finish:info[UIImagePickerControllerMediaURL] ?: info[UIImagePickerControllerOriginalImage]];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker { [self finish:nil]; }

@end
