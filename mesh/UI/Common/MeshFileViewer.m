#import "MeshMP4Sanitize.h"
#import "MeshFileViewer.h"
#import <MediaPlayer/MediaPlayer.h>
#import "MeshCompat.h"
#import "MeshNotifications.h"
#import "MeshMediaCheck.h"
#import "MeshImageCodec.h"
#import "MeshImageViewer.h"
#import "MeshTextViewer.h"
#import "MeshPopup.h"
#import "MeshL10n.h"

static MeshFileViewer *gOpen;   // ein Video zur Zeit; hält sich bis zum Schließen

typedef NS_ENUM(NSInteger, MeshFileKind) { MeshFileClosed, MeshFileImage, MeshFileText, MeshFileVideo };

// Nach dem Inhalt, nicht nach Name oder MIME (die setzt der Absender).
static MeshFileKind kindOf(NSData *data, NSString *mime) {
    if ([MeshMediaCheck isAcceptableImage:data formats:MeshImageJPEG | MeshImagePNG]) return MeshFileImage;
    if ([mime hasPrefix:@"text/plain"] && data.length <= 256 * 1024
        && [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]) return MeshFileText;
    const uint8_t *b = data.bytes;
    if ([mime isEqualToString:@"video/mp4"] && data.length > 12 && !memcmp(b + 4, "ftyp", 4)) return MeshFileVideo;
    return MeshFileClosed;
}

@implementation MeshFileViewer {
    NSString *_dir;
    MPMoviePlayerViewController *_player;
}

+ (BOOL)isVideo:(NSData *)data mime:(NSString *)mime { return kindOf(data, mime) == MeshFileVideo; }

+ (BOOL)canOpen:(NSData *)data mime:(NSString *)mime { return kindOf(data, mime) != MeshFileClosed; }

+ (void)open:(NSData *)data name:(NSString *)name mime:(NSString *)mime from:(UIViewController *)host {
    switch (kindOf(data, mime)) {
        case MeshFileImage: {
            UIImage *img = [MeshImageCodec imageFromData:data formats:MeshImageJPEG | MeshImagePNG];
            if (img) [host mesh_present:[[MeshImageViewer alloc] initWithImage:img] animated:YES];
            return;
        }
        case MeshFileText: {
            NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            [host mesh_present:[[MeshTextViewer alloc] initWithTitle:name text:text] animated:YES];
            return;
        }
        case MeshFileVideo:
            [self playVideo:data from:host];
            return;
        case MeshFileClosed:
            [MeshPopup info:L(@"This file type is not opened on this device for security reasons.")];
            return;
    }
}

+ (void)playVideo:(NSData *)data from:(UIViewController *)host {
    // Der System-Player bekommt nie die empfangene Datei, nur eine von Mesh neu verpackte (MeshMP4Sanitize)
    data = MeshMP4Sanitize(data, NULL);
    if (!data) { [MeshPopup info:L(@"This video could not be checked safely and is not played.")]; return; }
    [gOpen close];
    MeshFileViewer *v = [[MeshFileViewer alloc] init];
    v->_dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"mesh-open-%u", arc4random()]];
    NSString *path = [v->_dir stringByAppendingPathComponent:@"video.mp4"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm createDirectoryAtPath:v->_dir withIntermediateDirectories:YES attributes:nil error:NULL]
        || ![data writeToFile:path options:NSDataWritingAtomic | NSDataWritingFileProtectionComplete error:NULL]) {
        [fm removeItemAtPath:v->_dir error:NULL];
        return;
    }
    gOpen = v;
    [[NSNotificationCenter defaultCenter] addObserver:v selector:@selector(close) name:MeshWillLockNotification object:nil];
    v->_player = [[MPMoviePlayerViewController alloc] initWithContentURL:[NSURL fileURLWithPath:path]];
    [[NSNotificationCenter defaultCenter] addObserver:v selector:@selector(close)
                                                 name:MPMoviePlayerPlaybackDidFinishNotification object:v->_player.moviePlayer];
    [host presentMoviePlayerViewControllerAnimated:v->_player];
}

- (void)close {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_player.moviePlayer stop]; _player = nil;
    if (_dir) [[NSFileManager defaultManager] removeItemAtPath:_dir error:NULL];
    _dir = nil;
    if (gOpen == self) gOpen = nil;
}

@end
