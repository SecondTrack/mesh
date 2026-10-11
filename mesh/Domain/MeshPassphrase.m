#import "MeshPassphrase.h"
#import "MeshCrypto.h"

static NSString *gDirectory;

@implementation MeshPassphrase

+ (void)setWordListDirectory:(NSString *)directory { gDirectory = [directory copy]; }

+ (NSArray *)languages { return @[@"de", @"en"]; }

+ (NSString *)defaultLanguage {
    NSString *app = [[[NSBundle mainBundle] preferredLocalizations] firstObject];
    return [app hasPrefix:@"de"] ? @"de" : @"en";
}

static NSArray *loadList(NSString *language) {
    NSString *name = [@"wordlist-" stringByAppendingString:language];
    NSString *path = gDirectory ? [gDirectory stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"txt"]]
                                : [[NSBundle mainBundle] pathForResource:name ofType:@"txt"];
    NSString *text = path ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL] : nil;
    NSMutableArray *list = [NSMutableArray array];
    for (NSString *w in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]])
        if (w.length) [list addObject:w];
    // Eine beschädigte Liste (zu kurz, doppelte Wörter) wäre unsicher: dann gar keine.
    return list.count == 7776 && [NSSet setWithArray:list].count == 7776 ? list : nil;
}

+ (NSArray *)wordListForLanguage:(NSString *)language {
    static NSMutableDictionary *lists;
    if (![[self languages] containsObject:language]) return nil;
    if (!lists) lists = [NSMutableDictionary dictionary];
    if (!lists[language]) lists[language] = loadList(language) ?: (id)[NSNull null];
    return lists[language] == [NSNull null] ? nil : lists[language];
}

// Gleichverteilt: Zufallszahl verwerfen, wenn sie im angeschnittenen Rest liegt.
static uint32_t uniform(uint32_t bound) {
    uint32_t limit = UINT32_MAX - UINT32_MAX % bound;
    for (;;) {
        NSData *r = [MeshCrypto randomBytes:4];
        if (r.length != 4) return UINT32_MAX;
        uint32_t v = *(const uint32_t *)r.bytes;
        if (v < limit) return v % bound;
    }
}

+ (NSArray *)randomWords:(NSUInteger)count language:(NSString *)language {
    NSArray *list = [self wordListForLanguage:language];
    if (!list) return nil;
    NSMutableArray *out = [NSMutableArray array];
    for (NSUInteger i = 0; i < count; i++) {
        uint32_t n = uniform((uint32_t)list.count);
        if (n >= list.count) return nil;
        [out addObject:list[n]];
    }
    return out;
}

+ (NSString *)normalize:(NSString *)input {
    NSString *lower = [[input ?: @"" lowercaseString] stringByFoldingWithOptions:NSDiacriticInsensitiveSearch locale:nil];
    NSMutableArray *words = [NSMutableArray array];
    for (NSString *w in [lower componentsSeparatedByCharactersInSet:[[NSCharacterSet letterCharacterSet] invertedSet]])
        if (w.length) [words addObject:w];
    return [words componentsJoinedByString:@" "];
}

+ (NSUInteger)knownWordsIn:(NSString *)normalized {
    NSMutableSet *known = [NSMutableSet set];
    for (NSString *language in [self languages]) [known addObjectsFromArray:[self wordListForLanguage:language] ?: @[]];
    NSUInteger n = 0;
    for (NSString *w in [normalized componentsSeparatedByString:@" "]) if ([known containsObject:w]) n++;
    return n;
}

+ (double)bitsForWords:(NSUInteger)count { return count * log2(7776.0); }

@end
