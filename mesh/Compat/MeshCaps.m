#import "MeshCaps.h"
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

@implementation MeshCaps

+ (BOOL)hasCamera {
    return [UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera];
}

+ (BOOL)hasMicrophone {
    AVAudioSession *s = [AVAudioSession sharedInstance];
    // inputAvailable ab iOS 6, davor inputIsAvailable (ab iOS 3, in iOS 6 veraltet).
    if ([s respondsToSelector:@selector(isInputAvailable)]) return s.inputAvailable;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return s.inputIsAvailable;
#pragma clang diagnostic pop
}

@end
