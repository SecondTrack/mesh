#import "MeshJSON.h"
#import "MeshJSONCodec.h"

// NSJSONSerialization unter iOS 5/6 kennt keine Tiefengrenze: "[[[[…" vom Relay würde den
// 512-KB-Stack des Lese-Threads sprengen. Darum vorher zählen, mit derselben Grenze wie MeshJSONCodec.
// Gezählt wird in UTF-8. Der System-Parser erkennt UTF-16/32 an Nullbytes und läse dieselben Bytes
// anders; JSON von Relays enthält nie ein rohes Nullbyte, solche Daten werden deshalb abgelehnt.
static BOOL nestingWithinLimit(NSData *data) {
    if (memchr(data.bytes, 0, data.length)) return NO;
    const unsigned char *b = data.bytes;
    int depth = 0; BOOL inString = NO;
    for (NSUInteger i = 0; i < data.length; i++) {
        unsigned char c = b[i];
        if (inString) {
            if (c == '\\') i++;
            else if (c == '"') inString = NO;
        } else if (c == '"') {
            inString = YES;
        } else if (c == '[' || c == '{') {
            if (++depth > MeshJSONMaxDepth) return NO;
        } else if (c == ']' || c == '}') {
            depth--;
        }
    }
    return YES;
}

@implementation MeshJSON

+ (id)objectWithData:(NSData *)data {
    if (!data.length || !nestingWithinLimit(data)) return nil;
    Class sys = NSClassFromString(@"NSJSONSerialization");
    if (sys) return [sys JSONObjectWithData:data options:0 error:NULL];
    return [MeshJSONCodec objectWithData:data];
}

+ (NSData *)dataWithObject:(id)object {
    if (!object) return nil;
    Class sys = NSClassFromString(@"NSJSONSerialization");
    if (sys) {
        if (![sys isValidJSONObject:object]) return nil;
        return [sys dataWithJSONObject:object options:0 error:NULL];
    }
    return [MeshJSONCodec dataWithObject:object];
}

@end
