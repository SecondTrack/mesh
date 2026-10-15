#import "MeshCustomEmoji.h"

static const NSUInteger kMaxName = 32;   // längster erlaubter Name; Codes darüber sind nie bekannt

@implementation MeshCustomEmoji

+ (NSArray *)names {
    static NSArray *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        names = @[@"frosch_grinsen", @"frosch_traenenlachen", @"frosch_herzaugen", @"frosch_schmunzeln", @"frosch_kuss",
                  @"frosch_schrei", @"frosch_angstschweiss", @"frosch_grimmig", @"frosch_verliebt", @"frosch_cool",
                  @"frosch_clown", @"frosch_schnauben", @"frosch_staunen", @"frosch_heulen", @"frosch_traurig",
                  @"frosch_denken", @"frosch_invader", @"frosch_roboter"];
    });
    return names;
}

static NSSet *nameSet(void) {
    static NSSet *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ set = [NSSet setWithArray:[MeshCustomEmoji names]]; });
    return set;
}

+ (BOOL)isName:(NSString *)key { return key && [nameSet() containsObject:key]; }

+ (NSString *)codeForName:(NSString *)name { return [NSString stringWithFormat:@":%@:", name]; }

+ (NSUInteger)codeAt:(const unichar *)b length:(NSUInteger)n index:(NSUInteger)i name:(NSString **)name {
    if (i >= n || b[i] != ':') return 0;
    NSUInteger j = i + 1;
    while (j < n && j - i - 1 <= kMaxName && ((b[j] >= 'a' && b[j] <= 'z') || b[j] == '_')) j++;
    if (j >= n || b[j] != ':' || j == i + 1 || j - i - 1 > kMaxName) return 0;
    NSString *s = [NSString stringWithCharacters:b + i + 1 length:j - i - 1];
    if (![nameSet() containsObject:s]) return 0;
    if (name) *name = s;
    return j + 1 - i;
}

+ (NSRange)codeEndingIn:(NSString *)text at:(NSUInteger)end {
    end = MIN(end, text.length);
    if (end < 3 || [text characterAtIndex:end - 1] != ':') return NSMakeRange(NSNotFound, 0);
    unichar stackBuf[256];
    unichar *b = end <= 256 ? stackBuf : malloc(end * sizeof(unichar));
    [text getCharacters:b range:NSMakeRange(0, end)];
    NSRange found = NSMakeRange(NSNotFound, 0);
    for (NSUInteger i = 0; i < end;) {
        NSUInteger len = [self codeAt:b length:end index:i name:NULL];
        if (len && i + len == end) { found = NSMakeRange(i, len); break; }
        i += len ? len : 1;
    }
    if (b != stackBuf) free(b);
    return found;
}

@end
