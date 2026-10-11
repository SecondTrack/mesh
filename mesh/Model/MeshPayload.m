#import "MeshPayload.h"
#import "MeshBase64.h"

static NSString *const kImage   = @"mesh:img";
static NSString *const kVoice   = @"mesh:voc:";
static NSString *const kFile    = @"\1mesh:file:";
static NSString *const kContact = @"mesh:contact:";
static NSString *const kNotice  = @"ttl:";
static NSString *const kKeyNotice = @"key:changed";
static NSString *const kOldImage = @"mesh:img:", *const kOldVoice = @"mesh:voice:";   // ältere iPod-Versionen
static const int kMaxVoiceSeconds = 3600;

static int clampSeconds(NSString *s) { return MAX(0, MIN(kMaxVoiceSeconds, s.intValue)); }

@implementation MeshPayload {
    NSString *_body;   // Base64-Teil, noch nicht dekodiert
}

+ (MeshPayloadKind)kindOf:(NSString *)content {
    if ([content hasPrefix:kImage]) return MeshPayloadImage;   // auch kOldImage
    if ([content hasPrefix:kVoice] || [content hasPrefix:kOldVoice]) return MeshPayloadVoice;
    if ([content hasPrefix:kFile]) return MeshPayloadFile;
    if ([content hasPrefix:kContact]) return MeshPayloadContact;
    return MeshPayloadText;
}

// Hinweise entstehen nur lokal; ein Text "ttl:…" vom Gegenüber bleibt Text.
+ (instancetype)parseNotice:(NSString *)content {
    if ([content isEqualToString:kKeyNotice]) {
        MeshPayload *p = [[self alloc] init];
        p->_kind = MeshPayloadNotice;
        p->_keyChanged = YES;
        return p;
    }
    if (![content hasPrefix:kNotice]) return nil;
    NSArray *parts = [[content substringFromIndex:kNotice.length] componentsSeparatedByString:@":"];
    MeshPayload *p = [[self alloc] init];
    p->_kind = MeshPayloadNotice;
    p->_seconds = MAX(0, [parts[0] intValue]);
    p->_byMe = parts.count > 1 && [parts[1] isEqualToString:@"1"];
    return p;
}

+ (instancetype)parse:(NSString *)content {
    MeshPayload *p = [[self alloc] init];
    p->_kind = [self kindOf:content];
    p->_body = @"";
    switch (p->_kind) {
        case MeshPayloadImage:
            p->_body = [content substringFromIndex:([content hasPrefix:kOldImage] ? kOldImage : kImage).length];
            break;
        case MeshPayloadVoice: {
            BOOL old = [content hasPrefix:kOldVoice];
            NSString *rest = [content substringFromIndex:(old ? kOldVoice : kVoice).length];
            NSRange sep = [rest rangeOfString:old ? @":" : @"|"];
            if (sep.location == NSNotFound) break;
            p->_seconds = clampSeconds([rest substringToIndex:sep.location]);
            p->_body = [rest substringFromIndex:sep.location + 1];
            break;
        }
        case MeshPayloadFile: {
            NSString *rest = [content substringFromIndex:kFile.length];
            NSRange nl = [rest rangeOfString:@"\n"];
            if (nl.location == NSNotFound) break;
            NSString *head = [rest substringToIndex:nl.location];
            NSRange sep = [head rangeOfString:@"\1"];
            p->_fileName = sep.location == NSNotFound ? head : [head substringToIndex:sep.location];
            p->_fileMime = sep.location == NSNotFound ? @"" : [head substringFromIndex:sep.location + 1];
            p->_body = [rest substringFromIndex:nl.location + 1];
            break;
        }
        case MeshPayloadContact: {
            NSString *rest = [content substringFromIndex:kContact.length];
            NSRange nl = [rest rangeOfString:@"\n"];
            p->_text = nl.location == NSNotFound ? @"" : [rest substringToIndex:nl.location];
            p->_code = nl.location == NSNotFound ? rest : [rest substringFromIndex:nl.location + 1];
            break;
        }
        case MeshPayloadText:
        case MeshPayloadNotice:
            p->_kind = MeshPayloadText;
            p->_text = [content copy] ?: @"";
            break;
    }
    return p;
}

+ (NSString *)markerForKind:(MeshPayloadKind)kind seconds:(int)seconds {
    switch (kind) {
        case MeshPayloadImage:  return kImage;
        case MeshPayloadVoice:  return [NSString stringWithFormat:@"%@%d|", kVoice, seconds];
        case MeshPayloadFile:   return kFile;
        case MeshPayloadText:
        case MeshPayloadNotice:
        case MeshPayloadContact: return nil;   // klein genug, um ganz geladen zu werden
    }
    return nil;
}

+ (NSString *)contentWithImage:(NSData *)jpeg {
    return [kImage stringByAppendingString:[MeshBase64 encode:jpeg]];
}

+ (NSString *)contentWithVoice:(NSData *)audio seconds:(int)seconds {
    return [NSString stringWithFormat:@"%@%d|%@", kVoice, seconds, [MeshBase64 encode:audio]];
}

// Name und MIME dürfen die Trenner nicht enthalten.
static NSString *headerField(NSString *s) {
    NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@"\1\n\r"];
    return [[s ?: @"" componentsSeparatedByCharactersInSet:bad] componentsJoinedByString:@""];
}

+ (NSString *)contentWithFile:(NSData *)data name:(NSString *)name mime:(NSString *)mime {
    return [NSString stringWithFormat:@"%@%@\1%@\n%@", kFile, headerField(name), headerField(mime), [MeshBase64 encode:data]];
}

+ (NSString *)contentWithContactName:(NSString *)name code:(NSString *)code {
    return [NSString stringWithFormat:@"%@%@\n%@", kContact, headerField(name), code];
}

+ (NSString *)noticeTimer:(int)seconds byMe:(BOOL)byMe {
    return [NSString stringWithFormat:@"%@%d:%d", kNotice, seconds, byMe ? 1 : 0];
}

+ (NSString *)noticeKeyChanged { return kKeyNotice; }

- (NSData *)data {
    if (!_body.length) return nil;
    NSData *d = [MeshBase64 decode:_body];
    return d.length ? d : nil;
}

@end
