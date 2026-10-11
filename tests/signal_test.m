// Signal zwischen zwei MeshSignal: Aufbau über Bundle mit und ohne Einmal-Schlüssel, Antworten,
// Reihenfolge durcheinander, Doppeltes, Neuaufbau, Vertrauen, Sicherheitsnummer, Speichern.
// Die Gegenprobe mit libsignal (Android) macht tools/dev/signal-interop.
#import "MeshTest.h"
#import "MeshSignal.h"
#import "MeshSignalBundle.h"
#import "MeshSignalWire.h"
#import "MeshBase64.h"

@interface MemorySignalStorage : NSObject <MeshSignalStorage>
@property (nonatomic) NSMutableDictionary *values;
@end
@implementation MemorySignalStorage
- (instancetype)init { if ((self = [super init])) _values = [NSMutableDictionary dictionary]; return self; }
- (NSData *)signalValueForKey:(NSString *)key { return _values[key]; }
- (BOOL)setSignalValue:(NSData *)value forKey:(NSString *)key {
    if (value) _values[key] = [value copy]; else [_values removeObjectForKey:key];
    return YES;
}
@end

static NSData *seed(uint8_t b) { uint8_t s[32]; memset(s, b, 32); return [NSData dataWithBytes:s length:32]; }
static NSString *A = @"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
static NSString *B = @"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

int main(void) { @autoreleasepool {
    MemorySignalStorage *as = [MemorySignalStorage new], *bs = [MemorySignalStorage new];
    MeshSignal *alice = [[MeshSignal alloc] initWithStorage:as seed:seed(1)];
    MeshSignal *bob = [[MeshSignal alloc] initWithStorage:bs seed:seed(2)];
    check(alice && bob, "init");
    check([[[MeshSignal alloc] initWithStorage:[MemorySignalStorage new] seed:seed(1)].identityKey isEqualToData:alice.identityKey], "identity from nsec");

    NSString *bobBundle = [bob bundleWithFreshOneTimeKey];
    MeshSignalBundle *parsed = [MeshSignalBundle parse:bobBundle];
    check(parsed.oneTimeKey && parsed.signedPreKeyId == 1 && [parsed signatureValid], "bundle with one-time key");
    check([bobBundle rangeOfString:@"="].location == NSNotFound && [bobBundle rangeOfString:@"+"].location == NSNotFound, "base64url");
    check(![MeshSignalBundle parse:[bob bundle]].oneTimeKey && [MeshSignal bundle:bobBundle sameIdentityAs:[bob bundle]], "static bundle");

    // Alice beginnt
    check(![alice encrypt:@"x" to:B bundle:nil verified:NO refused:NULL], "no session without bundle");
    NSString *c1 = [alice encrypt:@"Hallo Bob" to:B bundle:bobBundle verified:NO refused:NULL];
    NSString *c2 = [alice encrypt:@"zweite" to:B bundle:bobBundle verified:NO refused:NULL];
    check([c1 hasPrefix:@"sg1:p:"] && [c2 hasPrefix:@"sg1:p:"], "prekey messages until answered");
    check([[bob decrypt:c2 from:A verified:NO] isEqualToString:@"zweite"], "out of order prekey");
    check([[bob decrypt:c1 from:A verified:NO] isEqualToString:@"Hallo Bob"], "first after second");
    check([bob decrypt:c1 from:A verified:NO] == nil, "duplicate rejected");
    check(bs.values[[NSString stringWithFormat:@"pk.%u", parsed.oneTimeId]] == nil, "one-time key used up");

    // Bob antwortet: ab jetzt normale Nachrichten
    NSString *r1 = [bob encrypt:@"Hi Alice" to:A bundle:nil verified:NO refused:NULL];
    check([r1 hasPrefix:@"sg1:m:"], "reply is a normal message");
    check([[alice decrypt:r1 from:B verified:NO] isEqualToString:@"Hi Alice"], "alice reads reply");
    NSString *c3 = [alice encrypt:@"danke" to:B bundle:bobBundle verified:NO refused:NULL];
    check([c3 hasPrefix:@"sg1:m:"] && [[bob decrypt:c3 from:A verified:NO] isEqualToString:@"danke"], "acknowledged session");

    // Viele Nachrichten, gemischte Richtungen und Reihenfolge
    NSMutableArray *batch = [NSMutableArray array];
    for (int i = 0; i < 30; i++) [batch addObject:[bob encrypt:[NSString stringWithFormat:@"n%d", i] to:A bundle:nil verified:NO refused:NULL]];
    BOOL all = YES;
    for (int i = 29; i >= 0; i -= 2) all &= [[alice decrypt:batch[i] from:B verified:NO] isEqualToString:[NSString stringWithFormat:@"n%d", i]];
    NSString *mid = [alice encrypt:@"zwischendurch" to:B bundle:nil verified:NO refused:NULL];
    for (int i = 0; i < 30; i += 2) all &= [[alice decrypt:batch[i] from:B verified:NO] isEqualToString:[NSString stringWithFormat:@"n%d", i]];
    all &= [[bob decrypt:mid from:A verified:NO] isEqualToString:@"zwischendurch"];
    check(all, "30 messages, reversed and interleaved");

    // Gespeichert: neue Instanzen lesen weiter
    MeshSignal *bob2 = [[MeshSignal alloc] initWithStorage:bs seed:seed(2)];
    NSString *c4 = [alice encrypt:@"nach Neustart" to:B bundle:nil verified:NO refused:NULL];
    check([[bob2 decrypt:c4 from:A verified:NO] isEqualToString:@"nach Neustart"], "survives restart");

    // Alice verliert ihre Sitzung und baut neu auf (statisches Bundle, ohne Einmal-Schlüssel)
    [alice forgetPeer:B];
    NSString *again = [alice encrypt:@"neu aufgebaut" to:B bundle:[bob bundle] verified:NO refused:NULL];
    check([again hasPrefix:@"sg1:p:"] && [[bob2 decrypt:again from:A verified:NO] isEqualToString:@"neu aufgebaut"], "rebuilt session");
    NSString *back = [bob2 encrypt:@"angekommen" to:A bundle:nil verified:NO refused:NULL];
    check([[alice decrypt:back from:B verified:NO] isEqualToString:@"angekommen"], "reply on rebuilt session");

    // Vertrauen: neue Identität für B. Verifiziert abgelehnt, unverifiziert übernommen.
    MeshSignal *mallory = [[MeshSignal alloc] initWithStorage:[MemorySignalStorage new] seed:seed(3)];
    NSString *fake = [mallory bundle];
    BOOL refused = NO;
    check([alice encrypt:@"x" to:B bundle:fake verified:YES refused:&refused] == nil && refused, "verified contact: changed identity refused");
    NSString *forged = [mallory encrypt:@"ich bin B" to:A bundle:[alice bundle] verified:NO refused:NULL];
    check([alice decrypt:forged from:B verified:YES] == nil, "verified contact: foreign identity refused");
    check([[alice decrypt:forged from:B verified:NO] isEqualToString:@"ich bin B"], "unverified: new identity accepted (TOFU)");

    // Kaputtes und Fremdes
    check([bob decrypt:@"sg1:m:AAAA" from:A verified:NO] == nil && [bob decrypt:@"sg1:x:AAAA" from:A verified:NO] == nil, "garbage");
    NSMutableData *bad = [[MeshBase64 decode:[c4 substringFromIndex:6]] mutableCopy];
    ((uint8_t *)bad.mutableBytes)[bad.length - 1] ^= 1;
    check([bob2 decrypt:[@"sg1:m:" stringByAppendingString:[MeshBase64 encode:bad]] from:A verified:NO] == nil, "bad MAC");
    NSString *other = [mallory bundleWithFreshOneTimeKey];
    NSMutableData *broken = [MeshBase64URLDecode(other) mutableCopy];
    ((uint8_t *)broken.mutableBytes)[80] ^= 1;   // Signatur
    check(![[MeshSignalBundle parse:MeshBase64URLEncode(broken)] signatureValid], "bad bundle signature");
    check([alice encrypt:@"x" to:@"cccc" bundle:MeshBase64URLEncode(broken) verified:NO refused:NULL] == nil, "no session from bad bundle");

    // Sicherheitsnummer: beide Seiten gleich
    NSArray *na = [alice safetyNumberWith:B myPubkey:A peerBundle:[bob bundle]];
    NSArray *nb = [bob safetyNumberWith:A myPubkey:B peerBundle:[alice bundle]];
    check(na.count == 12 && [na isEqualToArray:nb] && [na[0] length] == 5, "safety number symmetric");

    // Pool: nur die jüngsten Einmal-Schlüssel bleiben
    for (int i = 0; i < 730; i++) [bob bundleWithFreshOneTimeKey];
    NSUInteger keys = 0;
    for (NSString *k in bs.values) if ([k hasPrefix:@"pk."]) keys++;
    check(keys == 720, "one-time pool capped");
    return testsDone();
}}
