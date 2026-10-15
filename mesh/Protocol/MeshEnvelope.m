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
static NSString *const kGroup   = @"\1mesh:g:";       // Kopfzeile einer Gruppennachricht
static NSString *const kAnon    = @"\1mesh:anon:";    // Kopfzeile einer anonymen Team-Nachricht ("1")
static NSString *const kGInvite = @"\1mesh:gi:";
static NSString *const kGJoin   = @"\1mesh:gj:";
static NSString *const kGState  = @"\1mesh:gs:";
static NSString *const kGLeave  = @"\1mesh:gl:";
static NSString *const kGPicture = @"\1mesh:gp:";
static NSString *const kGPropose = @"\1mesh:gpr:";
static NSString *const kGVouch   = @"\1mesh:gvo:";
static NSString *const kGKey     = @"\1mesh:gk:";
static NSString *const kGLink    = @"\1mesh:glink:";   // Link-Karte (B10), gehört zu MeshPayload, hier nur zum Erkennen
static const NSUInteger kMaxGroupControl = 16 * 1024;   // Base64 einer Steueranweisung höchstens so lang
static const NSUInteger kMaxGroupPicture = 64 * 1024;   // gp: rohe Bildbytes höchstens so viele (B7)

static NSString *const kModeRead = @"read", *const kModeSent = @"sent";
static const int kMaxTimer = 365 * 24 * 3600;

static NSString *modeName(MeshTimerMode mode) { return mode == MeshTimerFromSent ? kModeSent : kModeRead; }

static int timerValue(NSString *s) { return MAX(0, MIN(kMaxTimer, s.intValue)); }

static NSString *base64Text(NSString *b64) {
    NSData *d = [MeshBase64 decode:b64];
    return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : nil;
}

// 16 Hex-Zeichen, klein; nil sonst.
static NSString *groupId(NSString *s) {
    return [MeshEnvelope isGroupId:s] ? s.lowercaseString : nil;
}

static BOOL base64Alphabet(NSString *b64) {
    static NSCharacterSet *bad;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        bad = [[NSCharacterSet characterSetWithCharactersInString:
                @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="] invertedSet];
    });
    return [b64 rangeOfCharacterFromSet:bad].location == NSNotFound;
}

// Base64 einer Gruppen-Steueranweisung: höchstens kMaxGroupControl, nur das Base64-Alphabet, UTF-8.
static NSString *groupText(NSString *b64) {
    if (b64.length > kMaxGroupControl || !base64Alphabet(b64)) return nil;
    if (!b64.length) return @"";
    return base64Text(b64);
}

// Hex fester Länge, klein; nil sonst.
static NSString *hexOf(NSString *s, NSUInteger length) {
    if (s.length != length) return nil;
    for (NSUInteger i = 0; i < length; i++) {
        unichar c = [s characterAtIndex:i];
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) return nil;
    }
    return s.lowercaseString;
}

// Base64 des Gruppenbilds: nicht leer, höchstens kMaxGroupPicture Bytes. nil sonst.
static NSData *groupPictureBytes(NSString *b64) {
    if (!b64.length || b64.length > (kMaxGroupPicture + 2) / 3 * 4 || !base64Alphabet(b64)) return nil;
    NSData *d = [MeshBase64 decode:b64];
    return d.length && d.length <= kMaxGroupPicture ? d : nil;
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
    // Gruppe und anonym höchstens einmal und nur gültig, sonst nichts davon anzeigen.
    BOOL broken = NO, header = NO;
    for (NSString *value = nil;;) {
        if (takeLine(&s, kMeta, &value)) [e parseMeta:value];
        else if (takeLine(&s, kBundle, &value)) e->_bundle = value;
        else if (takeLine(&s, kOnion, &value)) continue;
        else if (takeLine(&s, kGroup, &value)) { broken |= header || !groupId(value); header = YES; e->_group = groupId(value); }
        else if (takeLine(&s, kAnon, &value)) { broken |= e->_anon || ![value isEqualToString:@"1"]; e->_anon = YES; }
        else break;
    }
    if (broken || (e->_group && e->_anon)) return [e ignored];

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
    } else if ([s hasPrefix:kGInvite] || [s hasPrefix:kGState]) {
        e->_groupState = groupText([s substringFromIndex:kGInvite.length]);
        if (!e->_groupState.length) return [e ignored];
        e->_type = [s hasPrefix:kGInvite] ? MeshEnvelopeGroupInvite : MeshEnvelopeGroupState;
    } else if ([s hasPrefix:kGJoin]) {
        // "<gid>|<B64 Name>" oder (B10) "<gid>|<B64 Name>|<k>"
        NSArray *parts = [[s substringFromIndex:kGJoin.length] componentsSeparatedByString:@"|"];
        if (parts.count != 2 && parts.count != 3) return [e ignored];
        e->_group = groupId(parts[0]);
        e->_joinName = groupText(parts[1]);
        if (parts.count == 3 && !(e->_joinKey = hexOf(parts[2], 32))) return [e ignored];
        if (!e->_group || !e->_joinName) return [e ignored];
        e->_type = MeshEnvelopeGroupJoin;
    } else if ([s hasPrefix:kGPropose] || [s hasPrefix:kGVouch]) {
        // gpr: "<gid>|<C-pk>|<B64 Name>"; gvo: "<gid>|<Admin-pk>|<B64 Gruppenname>"
        BOOL propose = [s hasPrefix:kGPropose];
        NSArray *parts = [[s substringFromIndex:(propose ? kGPropose : kGVouch).length] componentsSeparatedByString:@"|"];
        if (parts.count != 3) return [e ignored];
        e->_group = groupId(parts[0]);
        e->_subject = hexOf(parts[1], 64);
        e->_subjectName = groupText(parts[2]);
        if (!e->_group || !e->_subject || !e->_subjectName) return [e ignored];
        e->_type = propose ? MeshEnvelopeGroupPropose : MeshEnvelopeGroupVouch;
    } else if ([s hasPrefix:kGKey]) {
        // "<gid>|<k>", k leer = geschlossen
        NSArray *parts = [[s substringFromIndex:kGKey.length] componentsSeparatedByString:@"|"];
        if (parts.count != 2) return [e ignored];
        e->_group = groupId(parts[0]);
        e->_joinKey = [parts[1] length] ? hexOf(parts[1], 32) : @"";
        if (!e->_group || !e->_joinKey) return [e ignored];
        e->_type = MeshEnvelopeGroupKey;
    } else if ([s hasPrefix:kGPicture]) {
        NSString *body = [s substringFromIndex:kGPicture.length];
        NSRange bar = [body rangeOfString:@"|"];
        if (bar.location == NSNotFound) return [e ignored];
        e->_group = groupId([body substringToIndex:bar.location]);
        e->_groupPicture = groupPictureBytes([body substringFromIndex:bar.location + 1]);
        if (!e->_group || !e->_groupPicture) return [e ignored];
        e->_type = MeshEnvelopeGroupPicture;
    } else if ([s hasPrefix:kGLeave]) {
        e->_group = groupId([s substringFromIndex:kGLeave.length]);
        if (!e->_group) return [e ignored];
        e->_type = MeshEnvelopeGroupLeave;
    } else {
        // Ein Steuermarker im Text stammt nie vom Nutzer: alte Echos oder Unbekanntes nicht anzeigen.
        // Ausnahmen: Datei (eigener Marker) und Link-Karte (B10, danach kein weiterer Marker).
        BOOL link = [s hasPrefix:kGLink] && [s rangeOfString:kControl options:0 range:NSMakeRange(kGLink.length, s.length - kGLink.length)].location == NSNotFound;
        if (!s.length || (!link && ![s hasPrefix:kFile] && [s rangeOfString:kControl].location != NSNotFound)) return [e ignored];
        e->_type = MeshEnvelopeMessage;
        e->_content = s;
    }
    // Gruppen-Kopfzeile nur vor Nachricht, Reaktion und Löschen; anonym nur vor Nachrichten.
    // Gruppen-Steueranweisungen nie mit Bundle oder Kopfzeile (so erzeugt sie keine Version).
    BOOL groupControl = e->_type == MeshEnvelopeGroupInvite || e->_type == MeshEnvelopeGroupJoin
                     || e->_type == MeshEnvelopeGroupState || e->_type == MeshEnvelopeGroupLeave
                     || e->_type == MeshEnvelopeGroupPicture || e->_type == MeshEnvelopeGroupPropose
                     || e->_type == MeshEnvelopeGroupVouch || e->_type == MeshEnvelopeGroupKey;
    if (e->_group && !groupControl && e->_type != MeshEnvelopeMessage && e->_type != MeshEnvelopeReaction && e->_type != MeshEnvelopeDelete)
        return [e ignored];
    if (groupControl && (e->_bundle.length || e->_anon || e->_cmid.length || header)) return [e ignored];
    if (e->_anon && e->_type != MeshEnvelopeMessage) return [e ignored];
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

#pragma mark - Gruppen und Team-Chat

+ (BOOL)isGroupId:(NSString *)gid {
    if (gid.length != 16) return NO;
    for (NSUInteger i = 0; i < 16; i++) {
        unichar c = [gid characterAtIndex:i];
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) return NO;
    }
    return YES;
}

+ (NSString *)inGroup:(NSString *)gid plain:(NSString *)plain {
    return [NSString stringWithFormat:@"%@%@\n%@", kGroup, gid, plain ?: @""];
}

static NSString *base64Of(NSString *text) { return [MeshBase64 encode:[(text ?: @"") dataUsingEncoding:NSUTF8StringEncoding]]; }

+ (NSString *)groupInvite:(NSString *)stateJSON { return [kGInvite stringByAppendingString:base64Of(stateJSON)]; }
+ (NSString *)groupState:(NSString *)stateJSON  { return [kGState stringByAppendingString:base64Of(stateJSON)]; }
+ (NSString *)groupLeave:(NSString *)gid        { return [kGLeave stringByAppendingString:gid]; }

+ (NSString *)groupPicture:(NSData *)bytes gid:(NSString *)gid {
    return [NSString stringWithFormat:@"%@%@|%@", kGPicture, gid, [MeshBase64 encode:bytes ?: [NSData data]]];
}

+ (NSString *)groupJoin:(NSString *)gid name:(NSString *)name {
    return [NSString stringWithFormat:@"%@%@|%@", kGJoin, gid, base64Of(name)];
}

+ (NSString *)groupJoin:(NSString *)gid name:(NSString *)name key:(NSString *)key {
    return [NSString stringWithFormat:@"%@%@|%@|%@", kGJoin, gid, base64Of(name), key ?: @""];
}

+ (NSString *)groupPropose:(NSString *)gid candidate:(NSString *)pk name:(NSString *)name {
    return [NSString stringWithFormat:@"%@%@|%@|%@", kGPropose, gid, pk, base64Of(name)];
}

+ (NSString *)groupVouch:(NSString *)gid admin:(NSString *)admin groupName:(NSString *)name {
    return [NSString stringWithFormat:@"%@%@|%@|%@", kGVouch, gid, admin, base64Of(name)];
}

+ (NSString *)groupKey:(NSString *)gid key:(NSString *)key {
    return [NSString stringWithFormat:@"%@%@|%@", kGKey, gid, key ?: @""];
}

+ (NSString *)anonMessage:(NSString *)text cmid:(NSString *)cmid {
    return [NSString stringWithFormat:@"%@1\n%@%@\n%@", kAnon, kMeta, cmid, text ?: @""];
}

+ (NSString *)newMessageId { return [MeshHex encode:[MeshCrypto randomBytes:8]]; }

@end
