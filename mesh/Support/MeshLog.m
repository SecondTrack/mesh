#import "MeshLog.h"

static NSString *logPath(void) {
    NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docs = (dirs.count ? dirs[0] : [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"]);
    return [docs stringByAppendingPathComponent:@"mesh.log"];
}

void MeshLogRemove(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *path = logPath();
    for (NSString *p in @[path, [path stringByAppendingString:@".old"], [path stringByAppendingString:@".prev"]])
        [fm removeItemAtPath:p error:NULL];
}

#ifdef DEBUG

void MeshLog(NSString *fmt, ...) {
    va_list args; va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSLog(@"[Mesh] %@", msg);

    NSString *path = logPath();
    [[NSFileManager defaultManager] createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    // Größe begrenzen: über 256 KB wird neu begonnen.
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
    if ([attrs fileSize] > 256 * 1024) [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], msg];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) { [line writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:NULL]; return; }
    [fh seekToEndOfFile];
    [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [fh closeFile];
}

#endif
