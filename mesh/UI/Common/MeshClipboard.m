#import "MeshClipboard.h"
#import "MeshPopup.h"
#import "MeshNotifications.h"

static NSString *gCopiedMessage;   // zuletzt kopierter Nachrichtentext, nur bis zum Sperren

@implementation MeshClipboard

+ (void)copyPublic:(NSString *)text confirmation:(NSString *)message {
    if (!text.length) return;
    [UIPasteboard generalPasteboard].string = text;
    [MeshPopup info:message];
}

+ (void)copyMessage:(NSString *)text {
    if (!text.length) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(forgetMessage)
                                                     name:MeshWillLockNotification object:nil];
    });
    gCopiedMessage = [text copy];
    [UIPasteboard generalPasteboard].string = text;
}

+ (void)forgetMessage {
    UIPasteboard *pb = [UIPasteboard generalPasteboard];
    if (gCopiedMessage && [pb.string isEqualToString:gCopiedMessage]) pb.string = @"";
    gCopiedMessage = nil;
}

@end
