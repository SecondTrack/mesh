#import "MeshEnvelope.h"
#import "MeshCrypto.h"
#import "MeshHex.h"
#import "MeshBase64.h"

static NSString *const kMeta    = @"\1mesh:x:";
static NSString *const kBundle  = @"\1mesh:mb:";
static NSString *const kOnion   = @"mesh:on:";
static NSString *const kReact   = @"\1mesh:rx:";
static NSString *const kDelete  = @"\1mesh:del:";
static NSString *const kClear   = @"\1mesh:clr:";
static NSString *const kTimer   = @"\1mesh:ttls:";
static NSString *const kHello   = @"mesh:hi:";
static NSString *const kChunk   = @"\1mesh:fc:";
static NSString *const kPicture = @"\1mesh:pic:";
static NSString *const kFile    = @"\1mesh:file:";   // gehört zu MeshPayload, hier nur zum Erkennen
static NSString *const kControl = @"\1mesh:";        // gemeinsamer Anfang aller Steuermarker

static NSString *const kModeRead = @"read", *const kModeSent = @"sent";
static const int kMaxTimer = 365 * 24 * 3600;

static NSString *modeName(MeshTimerMode mode) { return mode == MeshTimerFromSent ? kModeSent : kModeRead; }

static int timerValue(NSString *s) { return MAX(0, MIN(kMaxTimer, s.intValue)); }

static NSString *base64Text(NSString *b64) {
    NSData *d = [MeshBase64 decode:b64];
    return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : nil;
}

@implementation MeshEnvelope

// Kopfzeile mit Marker abtrennen: "<marker><wert>\n<rest>". NO, wenn s nicht so beginnt.
static BOOL takeLine(NSString **s, NSString *marker, NSString **value) {
    if (![*s hasPrefix:marker]) return NO;
    NSRange nl = [*s rangeOfString:@"\n"];
    if (nl.location == NSNotFound || nl.location <= marker.length) return NO;
    *value = [*s substringWithRange:NSMakeRange(marker.length, nl.location - marker.length)];
    *s = [*s substringFromIndex:nl.location + 1];
    return YES;
}

+ (instancetype)parse:(NSString *)plain {
    MeshEnvelope *e = [[self alloc] init];
    e->_cmid = @""; e->_replyTo = @""; e->_emoji = @""; e->_content = @"";
    NSString *s = plain ?: @"";

    // Kopfzeilen in beliebiger Reihenfolge abstreifen (Android setzt sie vor Text und Steuerung).
    for (NSString *value = nil;;) {
        if (takeLine(&s, kMeta, &value)) [e parseMeta:value];
        else if (takeLine(&s, kBundle, &value)) e->_bundle = value;
        else if (takeLine(&s, kOnion, &value)) continue;
        else break;
    }

    if ([s hasPrefix:kReact]) {
        NSString *body = [s substringFromIndex:kReact.length];
        NSRange bar = [body rangeOfString:@"|"];
        if (bar.location == NSNotFound || bar.location == 0) return [e ignored];
        e->_type = MeshEnvelopeReaction;
        e->_target = [body substringToIndex:bar.location];
        e->_emoji = [body substringFromIndex:bar.location + 1];
    } else if ([s hasPrefix:kDelete]) {
        e->_type = MeshEnvelopeDelete;
        e->_target = [s substringFromIndex:kDelete.length];
        if (!e->_target.length) return [e ignored];
    } else if ([s hasPrefix:kClear]) {
        e->_type = MeshEnvelopeClear;
    } else if ([s hasPrefix:kTimer]) {
        NSString *body = [s substringFromIndex:kTimer.length];
        NSRange bar = [body rangeOfString:@"|"];
        e->_type = MeshEnvelopeTimer;
        e->_timer = timerValue(bar.location == NSNotFound ? body : [body substringToIndex:bar.location]);
        e->_timerMode = bar.location != NSNotFound && [[body substringFromIndex:bar.location + 1] isEqualToString:kModeSent]
            ? MeshTimerFromSent : MeshTimerFromRead;
    } else if ([s isEqualToString:kHello]) {
        e->_type = MeshEnvelopeHello;
    } else if ([s hasPrefix:kPicture]) {
        e->_type = MeshEnvelopePicture;
        e->_picture = [[s substringFromIndex:kPicture.length] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    } else if ([s hasPrefix:kChunk]) {
        if (![e parseChunk:[s substringFromIndex:kChunk.length]]) return [e ignored];
        e->_type = MeshEnvelopeFileChunk;
    } else {
        // Ein Steuermarker im Text stammt nie vom Nutzer: alte Echos oder Unbekanntes nicht anzeigen.
        if (!s.length || (![s hasPrefix:kFile] && [s rangeOfString:kControl].location != NSNotFound)) return [e ignored];
        e->_type = MeshEnvelopeMessage;
        e->_content = s;
    }
    return e;
}

- (instancetype)ignored { _type = MeshEnvelopeIgnored; return self; }

// "<cmid>|r=<cmid>|t=<s>" bzw. "|tr=<s>"
- (void)parseMeta:(NSString *)meta {
    NSArray *parts = [meta componentsSeparatedByString:@"|"];
    _cmid = parts[0];
    for (NSUInteger i = 1; i < parts.count; i++) {
        NSString *p = parts[i];
        if ([p hasPrefix:@"r="]) _replyTo = [p substringFromIndex:2];
        else if ([p hasPrefix:@"tr="]) { _timer = timerValue([p substringFromIndex:3]); _timerMode = MeshTimerFromRead; }
        else if ([p hasPrefix:@"t="]) { _timer = timerValue([p substringFromIndex:2]); _timerMode = MeshTimerFromSent; }
    }
}

// "<fileId>|<index>|<anzahl>|b64(mime)|b64(name)[|thumb]\n<chunk>"
- (BOOL)parseChunk:(NSString *)body {
    NSRange nl = [body rangeOfString:@"\n"];
    if (nl.location == NSNotFound) return NO;
    NSArray *parts = [[body substringToIndex:nl.location] componentsSeparatedByString:@"|"];
    if (parts.count < 5) return NO;
    NSString *fileId = parts[0];
    // Die ID wird zum Dateinamen: nur das eigene Format (16 Hex) zulassen.
    if (fileId.length != 16 || ![MeshHex decode:fileId]) return NO;
    _fileId = fileId.lowercaseString;
    _chunkIndex = [parts[1] intValue];
    _chunkCount = [parts[2] intValue];
    _fileMime = base64Text(parts[3]);
    _fileName = base64Text(parts[4]);
    _thumbnail = parts.count > 5 ? parts[5] : @"";
    _chunk = [body substringFromIndex:nl.location + 1];
    return _chunkIndex >= 0 && _chunkCount > 0 && _chunkIndex < _chunkCount && _fileMime && _fileName;
}

#pragma mark - Senden

+ (NSString *)message:(NSString *)content cmid:(NSString *)cmid replyTo:(NSString *)replyTo
                timer:(int)seconds mode:(MeshTimerMode)mode bundle:(NSString *)bundle {
    NSMutableString *s = [NSMutableString string];
    if (cmid.length) {
        [s appendFormat:@"%@%@", kMeta, cmid];
        if (replyTo.length) [s appendFormat:@"|r=%@", replyTo];
        if (seconds > 0) [s appendFormat:@"|%@=%d", mode == MeshTimerFromSent ? @"t" : @"tr", seconds];
        [s appendString:@"\n"];
    }
    if (bundle.length) [s appendFormat:@"%@%@\n", kBundle, bundle];
    [s appendString:content ?: @""];
    return s;
}

+ (NSString *)reactionTo:(NSString *)target emoji:(NSString *)emoji {
    return [NSString stringWithFormat:@"%@%@|%@", kReact, target, emoji ?: @""];
}

+ (NSString *)deletionOf:(NSString *)target { return [kDelete stringByAppendingString:target]; }
+ (NSString *)clearChat { return kClear; }

+ (NSString *)timer:(int)seconds mode:(MeshTimerMode)mode {
    return [NSString stringWithFormat:@"%@%d|%@", kTimer, MAX(0, seconds), modeName(mode)];
}

+ (NSString *)helloWithBundle:(NSString *)bundle {
    return bundle.length ? [NSString stringWithFormat:@"%@%@\n%@", kBundle, bundle, kHello] : kHello;
}

+ (NSString *)picture:(NSString *)base64 { return [kPicture stringByAppendingString:base64 ?: @""]; }

+ (NSString *)newMessageId { return [MeshHex encode:[MeshCrypto randomBytes:8]]; }

@end
