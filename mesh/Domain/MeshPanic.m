#import "MeshPanic.h"
#import "MeshKeychain.h"
#import "MeshCrypto.h"
#import "MeshHex.h"
#import "MeshMemory.h"
#import "MeshTime.h"

static NSString *const kCodeword = @"panic.codeword";   // "<Länge in UTF-8-Bytes> <gesetzt um>\n<Token je Identität>…"
static const long long kSenderClockSlack = 3600;        // Auslöser dürfen so viel vor dem Setzen datiert sein
static NSString *const kPin = @"panic.pin";             // Salz (16) ‖ Prüfwert (32)
static const int kTriggerIterations = 120000;           // wie Android, sonst passt das Token nicht
static const int kPinIterations = 40000;                // wie MeshVaultIterations
static NSString *const kPinMarker = @"mesh:duress:ok:v1";

// Standard: Schlüsselbund.
@interface MeshKeychainPanicStorage : NSObject <MeshPanicStorage>
@end
@implementation MeshKeychainPanicStorage
- (NSData *)panicDataNamed:(NSString *)name { return [MeshKeychain read:name status:NULL]; }
// Das Token muss auch bei gesperrtem Gerät lesbar sein, sonst greift die Notlöschung gerade dann
// nicht, wenn jemand das Gerät hat. Es ist nur ein PBKDF2-Wert; die Panik-PIN bleibt streng.
- (BOOL)setPanicData:(NSData *)data named:(NSString *)name {
    if (!data) return [MeshKeychain remove:name] == errSecSuccess;
    OSStatus st = [name isEqualToString:kCodeword] ? [MeshKeychain writeReadableWhileLocked:data account:name]
                                                  : [MeshKeychain write:data account:name];
    return st == errSecSuccess;
}
@end

@implementation MeshPanic {
    id<MeshPanicStorage> _storage;
}

- (instancetype)init { return [self initWithStorage:[MeshKeychainPanicStorage new]]; }

- (instancetype)initWithStorage:(id<MeshPanicStorage>)storage {
    if ((self = [super init])) _storage = storage;
    return self;
}

+ (NSString *)triggerFor:(NSString *)codeword target:(NSString *)pubkeyHex {
    NSString *trimmed = [codeword stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!trimmed.length || pubkeyHex.length != 64) return nil;
    NSData *salt = [[@"mesh:panic:v2:" stringByAppendingString:pubkeyHex] dataUsingEncoding:NSUTF8StringEncoding];
    NSData *key = [MeshCrypto pbkdf2:trimmed salt:salt iters:kTriggerIterations];
    NSString *token = key.length == 32 ? [@"p2:" stringByAppendingString:[MeshHex encode:key]] : nil;
    MeshWipe(key);
    return token;
}

#pragma mark - Codewort

- (BOOL)setCodeword:(NSString *)codeword pubkeys:(NSArray *)pubkeys {
    NSString *trimmed = [codeword stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!trimmed.length) return [_storage setPanicData:nil named:kCodeword];
    // Die Länge spart beim Prüfen von Texten die teure Ableitung für fast jede Nachricht.
    NSMutableArray *lines = [NSMutableArray arrayWithObject:[NSString stringWithFormat:@"%lu %lld",
                             (unsigned long)[trimmed lengthOfBytesUsingEncoding:NSUTF8StringEncoding], MeshNow()]];
    for (NSString *pk in pubkeys) {
        NSString *token = [MeshPanic triggerFor:trimmed target:pk];
        if (!token) return NO;
        [lines addObject:token];
    }
    if (lines.count < 2) return NO;
    return [_storage setPanicData:[[lines componentsJoinedByString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding] named:kCodeword];
}

// Länge, dann die Token; nil, wenn keins gesetzt ist.
- (NSArray *)codewordRecord {
    NSData *d = [_storage panicDataNamed:kCodeword];
    NSArray *lines = d ? [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] componentsSeparatedByString:@"\n"] : nil;
    if (lines.count < 2) return nil;
    for (NSUInteger i = 1; i < lines.count; i++) if (![lines[i] hasPrefix:@"p2:"]) return nil;
    return lines;
}

- (BOOL)hasCodeword { return [self codewordRecord] != nil; }

- (NSUInteger)codewordIdentities { return MAX((NSInteger)[self codewordRecord].count - 1, 0); }

// Ein Token steht öffentlich im Tag: ein altes Auslöse-Event (vor dem Setzen dieses Codeworts,
// z.B. vor einer Notlöschung mit demselben Codewort) darf nicht noch einmal löschen.
- (BOOL)matchesTrigger:(NSString *)tagValue sentAt:(long long)createdAt {
    NSArray *record = [self codewordRecord];
    NSArray *head = [record.firstObject componentsSeparatedByString:@" "];
    long long setAt = head.count > 1 ? [head[1] longLongValue] : 0;
    return createdAt >= setAt - kSenderClockSlack && [self matchesTrigger:tagValue];
}

- (BOOL)matchesTrigger:(NSString *)tagValue {
    NSArray *record = [self codewordRecord];
    NSData *value = [tagValue dataUsingEncoding:NSUTF8StringEncoding];
    BOOL match = NO;
    for (NSUInteger i = 1; i < record.count && value; i++)
        match |= [MeshCrypto constantTimeEqual:[record[i] dataUsingEncoding:NSUTF8StringEncoding] to:value];
    return match;
}

- (BOOL)matchesText:(NSString *)text myPubkey:(NSString *)pubkeyHex {
    NSArray *record = [self codewordRecord];
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!record || [trimmed lengthOfBytesUsingEncoding:NSUTF8StringEncoding] != [record[0] integerValue]) return NO;
    return [self matchesTrigger:[MeshPanic triggerFor:trimmed target:pubkeyHex]];
}

#pragma mark - Panik-PIN

static NSData *pinCheck(NSString *pin, NSData *salt, NSData *secret) {
    NSMutableData *s = [salt mutableCopy];
    [s appendData:secret];
    NSData *key = [MeshCrypto pbkdf2:pin salt:s iters:kPinIterations];
    MeshWipe(s);
    NSData *check = key ? [MeshCrypto hmacSHA256:[kPinMarker dataUsingEncoding:NSUTF8StringEncoding] key:key] : nil;
    MeshWipe(key);
    return check;
}

- (BOOL)setPin:(NSString *)pin deviceSecret:(NSData *)secret {
    if (!pin.length || secret.length != 32) return NO;
    NSData *salt = [MeshCrypto randomBytes:16];
    NSData *check = pinCheck(pin, salt, secret);
    if (salt.length != 16 || check.length != 32) return NO;
    NSMutableData *record = [salt mutableCopy];
    [record appendData:check];
    return [_storage setPanicData:record named:kPin];
}

- (BOOL)hasPin { return [_storage panicDataNamed:kPin].length == 48; }

- (BOOL)matchesPin:(NSString *)pin deviceSecret:(NSData *)secret {
    NSData *record = [_storage panicDataNamed:kPin];
    if (record.length != 48 || secret.length != 32 || !pin.length) return NO;
    NSData *check = pinCheck(pin, [record subdataWithRange:NSMakeRange(0, 16)], secret);
    return [MeshCrypto constantTimeEqual:check to:[record subdataWithRange:NSMakeRange(16, 32)]];
}

- (void)clearPin { [_storage setPanicData:nil named:kPin]; }

- (void)clearAll {
    [_storage setPanicData:nil named:kCodeword];
    [self clearPin];
}

@end
