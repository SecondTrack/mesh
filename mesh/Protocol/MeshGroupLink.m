#import "MeshGroupLink.h"

static NSString *const kPrefix = @"meshg:1:";

static NSString *hexOf(NSString *s, NSUInteger length) {
    if (s.length != length) return nil;
    for (NSUInteger i = 0; i < length; i++) {
        unichar c = [s characterAtIndex:i];
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) return nil;
    }
    return s.lowercaseString;
}

@implementation MeshGroupLink

+ (instancetype)parse:(NSString *)text {
    if (![text isKindOfClass:[NSString class]] || text.length > 256) return nil;
    NSString *t = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (t.length < kPrefix.length || [[t substringToIndex:kPrefix.length] caseInsensitiveCompare:kPrefix] != NSOrderedSame) return nil;
    NSArray *parts = [[t substringFromIndex:kPrefix.length] componentsSeparatedByString:@":"];
    if (parts.count != 3) return nil;
    NSString *gid = hexOf(parts[0], 16), *admin = hexOf(parts[1], 64), *key = hexOf(parts[2], 32);
    if (!gid || !admin || !key) return nil;
    MeshGroupLink *l = [[self alloc] init];
    l->_gid = gid; l->_admin = admin; l->_key = key;
    l->_text = [NSString stringWithFormat:@"%@%@:%@:%@", kPrefix, gid, admin, key];
    return l;
}

+ (NSString *)linkWithGroup:(NSString *)gid admin:(NSString *)admin key:(NSString *)key {
    NSString *g = hexOf(gid, 16), *a = hexOf(admin, 64), *k = hexOf(key, 32);
    return g && a && k ? [NSString stringWithFormat:@"%@%@:%@:%@", kPrefix, g, a, k] : nil;
}

@end
