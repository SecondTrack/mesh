// signalinterop.m — MeshSignal von der Kommandozeile, für die Gegenprobe mit libsignal (Android).
// Zustand in einer Property-List-Datei; ein Aufruf = ein Schritt:
//
//   signalinterop <zustand> <seed-hex> bundle|static
//   signalinterop <zustand> <seed-hex> encrypt <peer-hex> <bundle oder -> <text>
//   signalinterop <zustand> <seed-hex> decrypt <peer-hex> <sg1:…>
//   signalinterop <zustand> <seed-hex> safety <peer-hex> <eigener-pubkey-hex> <peer-bundle>
//
// Bauen: tools/dev/build.sh signalinterop
#import <Foundation/Foundation.h>
#import "MeshSignal.h"
#import "MeshHex.h"

@interface FileSignalStorage : NSObject <MeshSignalStorage>
- (instancetype)initWithPath:(NSString *)path;
@end

@implementation FileSignalStorage {
    NSString *_path;
    NSMutableDictionary *_values;
}
- (instancetype)initWithPath:(NSString *)path {
    if ((self = [super init])) {
        _path = path;
        _values = [[NSDictionary dictionaryWithContentsOfFile:path] mutableCopy] ?: [NSMutableDictionary dictionary];
    }
    return self;
}
- (NSData *)signalValueForKey:(NSString *)key { return _values[key]; }
- (BOOL)setSignalValue:(NSData *)value forKey:(NSString *)key {
    if (value) _values[key] = value; else [_values removeObjectForKey:key];
    return [_values writeToFile:_path atomically:YES];
}
@end

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 4) { fprintf(stderr, "Aufruf: siehe Kopf von signalinterop.m\n"); return 2; }
        NSString *path = @(argv[1]), *cmd = @(argv[3]);
        MeshSignal *signal = [[MeshSignal alloc] initWithStorage:[[FileSignalStorage alloc] initWithPath:path]
                                                            seed:[MeshHex decode:@(argv[2])]];
        NSString *out = nil;
        if ([cmd isEqualToString:@"bundle"]) out = [signal bundleWithFreshOneTimeKey];
        else if ([cmd isEqualToString:@"static"]) out = [signal bundle];
        else if ([cmd isEqualToString:@"encrypt"] && argc >= 7)
            out = [signal encrypt:@(argv[6]) to:@(argv[4]) bundle:(strcmp(argv[5], "-") ? @(argv[5]) : nil) verified:NO refused:NULL];
        else if ([cmd isEqualToString:@"decrypt"] && argc >= 6)
            out = [signal decrypt:@(argv[5]) from:@(argv[4]) verified:NO];
        else if ([cmd isEqualToString:@"safety"] && argc >= 7)
            out = [[signal safetyNumberWith:@(argv[4]) myPubkey:@(argv[5]) peerBundle:@(argv[6])] componentsJoinedByString:@" "];
        if (!out) { printf("FEHLER\n"); return 1; }
        printf("%s\n", out.UTF8String);
    }
    return 0;
}
