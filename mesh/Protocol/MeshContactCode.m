#import "MeshContactCode.h"
#import "MeshBech32.h"
#import "MeshHex.h"

static const NSUInteger kMaxCode = 1024;   // npub 63 + .onion 62 + Bundle mit Einmal-Schlüssel ~240

static NSString *stripPrefix(NSString *s, NSString *prefix) {
    return s.length >= prefix.length && [[s substringToIndex:prefix.length] caseInsensitiveCompare:prefix] == NSOrderedSame
        ? [s substringFromIndex:prefix.length] : s;
}

@implementation MeshContactCode

+ (instancetype)parse:(NSString *)input {
    if (input.length > kMaxCode) return nil;
    NSString *s = [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    s = stripPrefix(stripPrefix(s, @"mesh:"), @"nostr:");
    MeshContactCode *c = [[self alloc] init];
    NSRange q = [s rangeOfString:@"?"];
    if (q.location != NSNotFound) {
        for (NSString *param in [[s substringFromIndex:q.location + 1] componentsSeparatedByString:@"&"]) {
            NSString *value = [[param substringFromIndex:MIN(param.length, [param rangeOfString:@"="].location + 1)]
                               stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if ([param hasPrefix:@"sig="] && value.length) c->_bundle = value;
        }
        s = [s substringToIndex:q.location];
    }
    s = [[s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lowercaseString];
    if ([s hasPrefix:@"npub"]) {
        NSString *hrp = nil;
        NSData *raw = [MeshBech32 decode:s hrp:&hrp];
        if (raw.length == 32 && [hrp isEqualToString:@"npub"]) c->_pubkey = [MeshHex encode:raw];
    } else if (s.length == 64 && [MeshHex decode:s].length == 32) {
        c->_pubkey = s;
    }
    return c->_pubkey ? c : nil;
}

+ (NSString *)codeWithNpub:(NSString *)npub bundle:(NSString *)bundle {
    NSString *code = [@"mesh:" stringByAppendingString:npub];
    return bundle.length ? [NSString stringWithFormat:@"%@?sig=%@", code, bundle] : code;
}

@end

NSString *MeshPubkeyFromContactInput(NSString *input) { return [MeshContactCode parse:input].pubkey; }
