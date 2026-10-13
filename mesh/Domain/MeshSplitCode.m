#import "MeshSplitCode.h"

static NSString *const kPrefix = @"meshp:";

// FNV-1a über die UTF-8-Bytes, 6 Hex-Zeichen reichen zum Zuordnen
static NSString *idOf(NSString *code) {
    const char *s = [code UTF8String]; uint32_t h = 2166136261u;
    for (; s && *s; s++) { h ^= (uint8_t)*s; h *= 16777619u; }
    return [NSString stringWithFormat:@"%06x", h & 0xffffff];
}

@implementation MeshSplitCode {
    NSMutableDictionary *_got;   // id -> @{@n: stück}
}

+ (NSArray *)partsOf:(NSString *)code { return [self partsOf:code count:MESH_SPLIT_PARTS]; }

+ (NSArray *)partsOf:(NSString *)code count:(NSUInteger)k {
    if (!code.length || k < 1 || k > 9) return nil;
    NSString *i = idOf(code); NSMutableArray *out = [NSMutableArray array];
    NSUInteger len = code.length, step = (len + k - 1) / k;
    for (NSUInteger n = 0; n < k; n++) {
        NSUInteger a = MIN(len, n * step), b = MIN(len, a + step);
        [out addObject:[NSString stringWithFormat:@"%@%lu/%lu:%@:%@", kPrefix, (unsigned long)n + 1, (unsigned long)k, i, [code substringWithRange:NSMakeRange(a, b - a)]]];
    }
    return out;
}

+ (BOOL)isPart:(NSString *)s { return [s hasPrefix:kPrefix]; }

- (NSString *)add:(NSString *)part {
    if (![MeshSplitCode isPart:part]) return nil;
    NSArray *f = [[part substringFromIndex:kPrefix.length] componentsSeparatedByString:@":"];
    if (f.count < 3) return nil;
    NSArray *nk = [f[0] componentsSeparatedByString:@"/"];
    if (nk.count != 2) return nil;
    NSInteger n = [nk[0] integerValue], k = [nk[1] integerValue];
    NSString *i = f[1];
    if (k < 1 || k > 9 || n < 1 || n > k || i.length != 6) return nil;
    NSString *piece = [[f subarrayWithRange:NSMakeRange(2, f.count - 2)] componentsJoinedByString:@":"];   // Stück darf ":" enthalten
    if (!_got) _got = [NSMutableDictionary dictionary];
    NSString *key = [NSString stringWithFormat:@"%@/%ld", i, (long)k];
    NSMutableDictionary *e = _got[key] ?: [NSMutableDictionary dictionary];
    e[@(n)] = piece; _got[key] = e; _total = k;
    NSMutableArray *miss = [NSMutableArray array]; NSMutableString *code = [NSMutableString string];
    for (NSInteger x = 1; x <= k; x++) { if (e[@(x)]) [code appendString:e[@(x)]]; else [miss addObject:@(x)]; }
    _missing = miss;
    if (miss.count) return nil;
    if ([idOf(code) isEqualToString:i]) return code;      // nur, wenn die Teile wirklich zusammenpassen
    // Alle Teile da, passen aber nicht (falsch gelesen oder verfälscht): von vorn sammeln, statt mit
    // leerer Liste festzuhängen.
    [_got removeObjectForKey:key];
    for (NSInteger x = 1; x <= k; x++) [miss addObject:@(x)];
    _missing = miss;
    return nil;
}
@end
