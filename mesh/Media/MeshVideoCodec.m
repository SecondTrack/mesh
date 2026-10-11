#import "MeshVideoCodec.h"
#import <AVFoundation/AVFoundation.h>

@implementation MeshVideoCodec

+ (void)mp4FromMovie:(NSURL *)movie maxBytes:(NSUInteger)maxBytes done:(void (^)(NSData *))done {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *name = [NSString stringWithFormat:@"mesh-video-%u.mp4", arc4random()];
    NSURL *out = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
    AVAssetExportSession *export = [[AVAssetExportSession alloc] initWithAsset:[AVURLAsset URLAssetWithURL:movie options:nil]
                                                                    presetName:AVAssetExportPresetLowQuality];
    export.outputURL = out;
    export.outputFileType = AVFileTypeMPEG4;
    export.shouldOptimizeForNetworkUse = YES;
    export.fileLengthLimit = maxBytes;
    export.metadata = @[];   // nil hieße: Metadaten der Aufnahme übernehmen (Ort, Gerät, Zeit)
    [export exportAsynchronouslyWithCompletionHandler:^{
        NSData *mp4 = export.status == AVAssetExportSessionStatusCompleted ? [NSData dataWithContentsOfURL:out] : nil;
        [fm removeItemAtURL:out error:NULL];
        [fm removeItemAtURL:movie error:NULL];
        if (mp4.length > maxBytes) mp4 = nil;
        dispatch_async(dispatch_get_main_queue(), ^{ done(mp4); });
    }];
}

+ (UIImage *)thumbnailOfMP4:(NSData *)mp4 maxSide:(CGFloat)maxSide {
    if (mp4.length < 12 || memcmp((const uint8_t *)mp4.bytes + 4, "ftyp", 4)) return nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"mesh-thumb-%u.mp4", arc4random()]];
    if (![mp4 writeToFile:path options:NSDataWritingAtomic | NSDataWritingFileProtectionComplete error:NULL]) return nil;
    AVAssetImageGenerator *gen = [[AVAssetImageGenerator alloc] initWithAsset:[AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil]];
    gen.appliesPreferredTrackTransform = YES;   // Hochkant-Aufnahmen aufrecht
    gen.maximumSize = CGSizeMake(maxSide, maxSide);
    CGImageRef cg = [gen copyCGImageAtTime:CMTimeMake(1, 10) actualTime:NULL error:NULL];
    if (!cg) cg = [gen copyCGImageAtTime:kCMTimeZero actualTime:NULL error:NULL];   // Clips unter 0,1 s
    [fm removeItemAtPath:path error:NULL];
    if (!cg) return nil;
    UIImage *img = [UIImage imageWithCGImage:cg];
    CGImageRelease(cg);
    return img;
}

@end
