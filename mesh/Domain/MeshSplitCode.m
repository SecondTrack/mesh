#import "MeshSplitCode.h"

static NSString *const kPrefix = @"meshp:";

// FNV-1a über die UTF-8-Bytes, 6 Hex-Zeichen reichen zum Zuordnen
static NSString *idOf(NSString *code) {
    const char *s = [code UTF8String]; uint32_t h = 2166136261u;
    for (; s && *s; s++) { h ^= (uint8_t)*s; h *= 16777619u; }
    return [NSString stringWithFormat:@"%06x", h & 0xffffff];
}

@implementation MeshSplitCode {
    NSMutableDictionary *_got;   // id -> @{@1: stück, @2: stück}
}

+ (NSArray *)partsOf:(NSString *)code {
    if (!code.length) return nil;
    NSUInteger half = (code.length + 1) / 2;
    NSString *i = idOf(code);
    return @[[NSString stringWithFormat:@"%@1/2:%@:%@", kPrefix, i, [code substringToIndex:half]],
             [NSString stringWithFormat:@"%@2/2:%@:%@", kPrefix, i, [code substringFromIndex:half]]];
}

+ (BOOL)isPart:(NSString *)s { return [s hasPrefix:kPrefix]; }

- (NSString *)add:(NSString *)part {
    if (![MeshSplitCode isPart:part]) return nil;
    NSArray *f = [[part substringFromIndex:kPrefix.length] componentsSeparatedByString:@":"];
    if (f.count < 3) return nil;
    NSInteger n = [f[0] hasPrefix:@"1/"] ? 1 : ([f[0] hasPrefix:@"2/"] ? 2 : 0);
    NSString *i = f[1];
    if (!n || i.length != 6) return nil;
    NSString *piece = [[f subarrayWithRange:NSMakeRange(2, f.count - 2)] componentsJoinedByString:@":"];   // Stück darf ":" enthalten
    if (!_got) _got = [NSMutableDictionary dictionary];
    NSMutableDictionary *e = _got[i] ?: [NSMutableDictionary dictionary];
    e[@(n)] = piece; _got[i] = e; _lastPart = n;
    if (!e[@1] || !e[@2]) return nil;
    NSString *code = [e[@1] stringByAppendingString:e[@2]];
    return [idOf(code) isEqualToString:i] ? code : nil;   // nur, wenn die Teile wirklich zusammenpassen
}
@end
