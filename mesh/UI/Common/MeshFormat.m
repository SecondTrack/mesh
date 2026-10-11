#import "MeshFormat.h"
#import "MeshPayload.h"
#import "MeshL10n.h"
#import "MeshText.h"

static const NSUInteger kPreviewMax = 80;

@implementation MeshFormat

+ (NSString *)shortTime:(long long)ts {
    // NSDateFormatter ist auf alten Geräten teuer: einmal anlegen (nur Main-Thread).
    static NSDateFormatter *time, *date;
    if (!time) {
        time = [[NSDateFormatter alloc] init]; time.dateFormat = @"HH:mm";
        date = [[NSDateFormatter alloc] init];   // Tag und Monat in der Reihenfolge der Region
        date.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"ddMM" options:0 locale:[NSLocale currentLocale]];
    }
    NSDate *d = [NSDate dateWithTimeIntervalSince1970:ts];
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSUInteger units = NSDayCalendarUnit | NSMonthCalendarUnit | NSYearCalendarUnit;
    BOOL today = [[cal components:units fromDate:d] isEqual:[cal components:units fromDate:[NSDate date]]];
    return [(today ? time : date) stringFromDate:d];
}

+ (NSString *)duration:(int)seconds {
    seconds = MAX(0, seconds);
    return [NSString stringWithFormat:@"%d:%02d", seconds / 60, seconds % 60];
}

+ (NSString *)pinWait:(NSTimeInterval)seconds {
    int s = (int)ceil(seconds);
    return LF(@"Too many attempts — try again in %d:%02d", s / 60, s % 60);
}

+ (NSString *)pinError:(MeshPinResult)result wait:(NSTimeInterval)wait {
    BOOL words = [[MeshSession shared] secretKind] == MeshSecretWords;
    switch (result) {
        case MeshPinOK:            return nil;
        case MeshPinWrong:         return words ? L(@"Wrong words") : L(@"Wrong PIN");
        case MeshPinLockedOut:     return [self pinWait:wait];
        case MeshPinDeviceChanged: return L(@"Key belongs to another device");
        case MeshPinKeychainBusy:  return L(@"Keychain not available — try again");
        case MeshPinStorageUnreadable: return L(@"Data can't be read — restart the app");
        case MeshPinWiped:         return nil;   // der Sperrbildschirm wechselt zur Einrichtung
        case MeshPinSameAsReal:    return words ? L(@"Must not be your real words") : L(@"Must not be your real PIN");
        case MeshPinSameAsPanic:   return words ? L(@"Must not be your panic code") : L(@"Must not be your panic PIN");
        case MeshPinFailed:        return L(@"Failed");
    }
    return nil;
}

+ (NSString *)preview:(NSString *)content kind:(NSInteger)kind {
    if (kind == MeshPayloadNotice) return [self notice:content peer:nil];
    MeshPayload *p = nil;
    switch ([MeshPayload kindOf:content]) {
        case MeshPayloadImage:   return L(@"Photo");
        case MeshPayloadVoice:   return L(@"Voice message");
        case MeshPayloadFile: {  // Kopfzeile "<SOH>mesh:file:Name<SOH>MIME": Video wie bei Android benennen
            NSRange nl = [content rangeOfString:@"\n"];
            NSString *head = nl.location == NSNotFound ? content : [content substringToIndex:nl.location];
            return [head rangeOfString:@"\1video/"].location != NSNotFound ? L(@"Video") : L(@"File");
        }
        case MeshPayloadContact: p = [MeshPayload parse:content]; return LF(@"Contact: %@", MeshCleanName(p.text));
        case MeshPayloadText:
        case MeshPayloadNotice:  break;
    }
    // Ohne Schreibrichtungszeichen: sonst könnte ein Fremder die Zeile in der Chatliste umdrehen.
    NSString *s = MeshCleanName(content);
    return s.length > kPreviewMax ? [MeshTruncate(s, kPreviewMax) stringByAppendingString:@" …"] : s;
}

+ (NSString *)timer:(int)seconds {
    switch (seconds) {
        case 0:      return L(@"Off");
        case 300:    return L(@"5 minutes");
        case 3600:   return L(@"1 hour");
        case 86400:  return L(@"1 day");
        case 604800: return L(@"1 week");
    }
    if (seconds % 86400 == 0) return LF(@"%d days", seconds / 86400);
    if (seconds % 3600 == 0)  return LF(@"%d h", seconds / 3600);
    return LF(@"%d min", MAX(1, seconds / 60));
}

+ (NSString *)fileDetail:(NSString *)name mime:(NSString *)mime bytes:(long long)bytes {
    NSString *type = [mime hasPrefix:@"video/"] ? L(@"Video") : [mime hasPrefix:@"audio/"] ? L(@"Audio")
                   : [mime hasPrefix:@"image/"] ? L(@"Photo") : name.pathExtension.length ? name.pathExtension.uppercaseString : L(@"File");
    NSString *size = bytes >= 1024 * 1024 ? [NSString stringWithFormat:@"%.1f MB", bytes / (1024.0 * 1024.0)]
                                          : [NSString stringWithFormat:@"%lld KB", MAX(1, (bytes + 1023) / 1024)];
    return [NSString stringWithFormat:@"%@ · %@", type, size];
}

+ (NSString *)notice:(NSString *)content peer:(NSString *)peerName {
    MeshPayload *n = [MeshPayload parseNotice:content];
    if (!n) return @"";
    if (n.keyChanged) return peerName ? LF(@"The safety number with %@ has changed", peerName) : L(@"Safety number changed");
    if (n.byMe) return n.seconds ? LF(@"You set disappearing messages to %@", [self timer:n.seconds])
                                 : L(@"You turned disappearing messages off");
    if (!peerName) return n.seconds ? LF(@"Disappearing messages: %@", [self timer:n.seconds]) : L(@"Disappearing messages off");
    return n.seconds ? LF(@"%@ set disappearing messages to %@", peerName, [self timer:n.seconds])
                     : LF(@"%@ turned disappearing messages off", peerName);
}

+ (NSString *)contactName:(NSString *)name accepted:(BOOL)accepted {
    return accepted ? name : LF(@"%@ · request", name);
}

@end
