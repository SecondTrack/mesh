#import "MeshSecretPrompt.h"
#import "MeshSession.h"
#import "MeshCompat.h"
#import "LockViewController.h"
#import "PassphraseLockViewController.h"

@implementation MeshSecretPrompt

+ (void)verifyFrom:(UIViewController *)from then:(void (^)(NSString *))next {
    UIViewController *host = from.navigationController ?: from;
    MESH_WEAK UIViewController *weakHost = host;
    void (^verified)(NSString *) = ^(NSString *secret) { [weakHost mesh_dismissPresentedAnimated:NO]; next(secret); };
    void (^cancel)(void) = ^{ [weakHost mesh_dismissPresentedAnimated:YES]; };
    UIViewController *screen;
    if ([[MeshSession shared] secretKind] == MeshSecretWords) {
        PassphraseLockViewController *lock = [[PassphraseLockViewController alloc] init];
        lock.verifyMode = YES;
        lock.onVerified = verified;
        lock.onCancel = cancel;
        screen = lock;
    } else {
        LockViewController *lock = [[LockViewController alloc] init];
        lock.verifyMode = YES;
        lock.onVerified = verified;
        lock.onCancel = cancel;
        screen = lock;
    }
    [host mesh_present:screen animated:YES];
}

@end
