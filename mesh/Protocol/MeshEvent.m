#import "MeshEvent.h"
#import "MeshTime.h"
#import "MeshKeys.h"
#import "MeshCrypto.h"
#import "MeshHex.h"

// Escaping nach NIP-01: genau \" \\ \n \r \t \b \f, alle anderen Zeichen unverändert:
// sonst ergäbe derselbe Inhalt bei anderen Clients eine andere Event-ID.
static void appendEscaped(NSMutableString *out, NSString *s) {
    [out appendString:@"\""];
    NSUInteger n = s.length, run = 0;   // Abschnitte ohne Sonderzeichen am Stück übernehmen
    for (NSUInteger i = 0; i < n; i++) {
        NSString *esc = nil;
        switch ([s characterAtIndex:i]) {
            case '"':  esc = @"\\\""; break;
            case '\\': esc = @"\\\\"; break;
            case '\n': esc = @"\\n";  break;
            case '\r': esc = @"\\r";  break;
            case '\t': esc = @"\\t";  break;
            case '\b': esc = @"\\b";  break;
            case '\f': esc = @"\\f";  break;
        }
        if (!esc) continue;
        if (i > run) [out appendString:[s substringWithRange:NSMakeRange(run, i - run)]];
        [out appendString:esc];
        run = i + 1;
    }
    if (n > run) [out appendString:[s substringWithRange:NSMakeRange(run, n - run)]];
    [out appendString:@"\""];
}

@implementation MeshEvent

+ (instancetype)kind:(NSInteger)kind content:(NSString *)content tags:(NSArray *)tags {
    MeshEvent *e = [[self alloc] init];
    e.kind = kind;
    e.content = content ?: @"";
    e.tags = tags ?: @[];
    return e;
}

- (BOOL)hasTag:(NSString *)name value:(NSString *)value {
    for (NSArray *tag in self.tags)
        if (tag.count >= 2 && [tag[0] isEqualToString:name] && [tag[1] isEqualToString:value]) return YES;
    return NO;
}

// Kanonische Serialisierung: [0,pubkey,created_at,kind,tags,content], keine Whitespaces.
- (NSString *)canonical {
    NSMutableString *s = [NSMutableString stringWithString:@"[0,"];
    appendEscaped(s, self.pubkey);
    [s appendFormat:@",%lld,%ld,[", self.createdAt, (long)self.kind];
    for (NSUInteger i = 0; i < self.tags.count; i++) {
        if (i) [s appendString:@","];
        NSArray *tag = self.tags[i];
        [s appendString:@"["];
        for (NSUInteger j = 0; j < tag.count; j++) {
            if (j) [s appendString:@","];
            appendEscaped(s, tag[j]);
        }
        [s appendString:@"]"];
    }
    [s appendString:@"],"];
    appendEscaped(s, self.content);
    [s appendString:@"]"];
    return s;
}

- (BOOL)signWithKeys:(MeshKeys *)keys {
    self.pubkey = [MeshHex encode:keys.xonlyPub];
    if (self.createdAt == 0) self.createdAt = MeshNow();

    NSData *ser = [[self canonical] dataUsingEncoding:NSUTF8StringEncoding];
    if (!ser) return NO;   // nicht als UTF-8 darstellbar (z.B. halbes Emoji), nichts Falsches signieren
    NSData *id32 = [MeshCrypto sha256:ser];
    self.eventId = [MeshHex encode:id32];

    NSData *sig = [keys schnorrSign:id32];
    if (!sig) return NO;
    self.sig = [MeshHex encode:sig];
    return YES;
}

- (BOOL)verify {
    if (!self.eventId || !self.pubkey || !self.sig) return NO;
    NSData *ser = [[self canonical] dataUsingEncoding:NSUTF8StringEncoding];
    if (!ser) return NO;
    NSData *id32 = [MeshCrypto sha256:ser];
    if (![[MeshHex encode:id32] isEqualToString:self.eventId]) return NO;  // ID muss passen
    return [MeshKeys schnorrVerify:[MeshHex decode:self.sig]
                            msg32:id32
                         xonlyPub:[MeshHex decode:self.pubkey]];
}

- (NSDictionary *)toJSONObject {
    return @{ @"id": self.eventId ?: @"",
              @"pubkey": self.pubkey ?: @"",
              @"created_at": @(self.createdAt),
              @"kind": @(self.kind),
              @"tags": self.tags ?: @[],
              @"content": self.content ?: @"",
              @"sig": self.sig ?: @"" };
}

// Kleinbuchstaben-Hex genau der erwarteten Länge (NIP-01).
static BOOL isHex(id v, NSUInteger len) {
    if (![v isKindOfClass:[NSString class]] || [v length] != len) return NO;
    static NSCharacterSet *notHex;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ notHex = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet]; });
    return [v rangeOfCharacterFromSet:notHex].location == NSNotFound;
}

static BOOL isInteger(id v) {
    return [v isKindOfClass:[NSNumber class]] && CFGetTypeID((__bridge CFTypeRef)v) != CFBooleanGetTypeID()
        && [v doubleValue] == floor([v doubleValue]);
}

// tags: Liste von Listen aus Strings.
static BOOL isTagList(id v) {
    if (![v isKindOfClass:[NSArray class]]) return NO;
    for (id tag in v) {
        if (![tag isKindOfClass:[NSArray class]]) return NO;
        for (id s in tag) if (![s isKindOfClass:[NSString class]]) return NO;
    }
    return YES;
}

// Nimmt nur Events an, die NIP-01 formal genügen; alles andere ist nil (Signatur prüft -verify).
+ (instancetype)fromJSONObject:(NSDictionary *)o {
    if (![o isKindOfClass:[NSDictionary class]]) return nil;
    if (!isHex(o[@"id"], 64) || !isHex(o[@"pubkey"], 64) || !isHex(o[@"sig"], 128)) return nil;
    if (!isInteger(o[@"created_at"]) || !isInteger(o[@"kind"])) return nil;
    long long created = [o[@"created_at"] longLongValue], kind = [o[@"kind"] longLongValue];
    if (created < 0 || kind < 0 || kind > 65535) return nil;
    if (![o[@"content"] isKindOfClass:[NSString class]] || !isTagList(o[@"tags"])) return nil;

    MeshEvent *e = [[self alloc] init];
    e.eventId   = o[@"id"];
    e.pubkey    = o[@"pubkey"];
    e.createdAt = created;
    e.kind      = (NSInteger)kind;
    e.tags      = o[@"tags"];
    e.content   = o[@"content"];
    e.sig       = o[@"sig"];
    return e;
}

@end
