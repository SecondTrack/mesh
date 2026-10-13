// Kontakt per 4 Wörtern hinzufügen (für iPods ohne Kamera). A zeigt 4 Wörter; Mesh legt seine Kontaktkarte
// (npub + Signal-Paket mit frischem Einmal-Schlüssel) verschlüsselt für 10 Minuten auf die Relays.
// B tippt die Wörter ein, Mesh holt und öffnet die Karte und legt den Kontakt an.
//
// Aus den Wörtern leitet scrypt (N = 16384, r = 8, p = 1) 64 Byte ab: die ersten 16 sind die Kennung
// auf dem Relay (d-Tag), die letzten 32 der Schlüssel der Karte (MeshSeal). Ohne die Wörter findet
// niemand die Karte und kann keine eigene unter derselben Kennung ablegen. Signiert wird mit einem
// Wegwerf-Schlüssel, damit die Kennung nicht neben dem eigenen npub steht. Liegen unter einer Kennung
// zwei verschiedene Karten, legt Mesh keinen Kontakt an (jemand versucht, sich dazwischenzuschieben).
#import "MeshSession+Internal.h"
#import "MeshRelayPool.h"
#import "MeshEvent.h"
#import "MeshKeys.h"
#import "MeshSeal.h"
#import "MeshScrypt.h"
#import "MeshCrypto.h"
#import "MeshHex.h"
#import "MeshContactCode.h"
#import "MeshL10n.h"

static const NSInteger kPairKind = 30078;           // anwendungseigene Daten (NIP-78)
static const long long kPairValid = 600;            // 10 Minuten
static const NSUInteger kPairWords = 4;
static NSString *const kPairContext = @"mesh-pair-v1";
static NSMutableDictionary *gPairWait;               // subId -> {events, key, tag}

static NSArray *pairWordList(void) {
    static NSArray *list; static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *p = [[NSBundle mainBundle] pathForResource:@"pairwords-en" ofType:@"txt"];
        NSString *t = p ? [NSString stringWithContentsOfFile:p encoding:NSUTF8StringEncoding error:NULL] : nil;
        NSMutableArray *a = [NSMutableArray array];
        for (NSString *l in [t componentsSeparatedByString:@"\n"]) if (l.length) [a addObject:l];
        list = a;
    });
    return list;
}

// klein, nur Buchstaben, je ein Leerzeichen; nil, wenn es nicht genau 4 bekannte Wörter sind
static NSString *normalizedWords(NSString *s) {
    NSMutableArray *words = [NSMutableArray array];
    NSCharacterSet *letters = [NSCharacterSet letterCharacterSet];
    NSMutableString *cur = [NSMutableString string];
    NSString *low = [s lowercaseString];
    for (NSUInteger i = 0; i <= low.length; i++) {
        unichar c = i < low.length ? [low characterAtIndex:i] : ' ';
        if ([letters characterIsMember:c]) [cur appendFormat:@"%C", c];
        else if (cur.length) { [words addObject:[cur copy]]; [cur setString:@""]; }
    }
    if (words.count != kPairWords) return nil;
    NSSet *known = [NSSet setWithArray:pairWordList()];
    for (NSString *w in words) if (![known containsObject:w]) return nil;
    return [words componentsJoinedByString:@" "];
}

static void derive(NSString *words, NSString **tag, NSData **key) {
    NSData *out = MeshScrypt([words dataUsingEncoding:NSUTF8StringEncoding], [kPairContext dataUsingEncoding:NSUTF8StringEncoding], 16384, 8, 1, 64);
    *tag = [MeshHex encode:[out subdataWithRange:NSMakeRange(0, 16)]];
    *key = [out subdataWithRange:NSMakeRange(32, 32)];
}

@implementation MeshSession (Pairing)

+ (BOOL)looksLikePairingWords:(NSString *)s { return normalizedWords(s) != nil; }

- (void)pairingWords:(void (^)(NSString *, NSDate *, NSString *))done {
    NSString *code = [self myContactCode];
    if (!code) { done(nil, nil, L(@"Mesh is locked.")); return; }
    if (![self anyRelayConnected]) { done(nil, nil, L(@"Not connected yet. Try again in a moment.")); return; }
    NSArray *list = pairWordList();
    if (list.count < 1000) { done(nil, nil, L(@"Word list missing.")); return; }
    NSMutableArray *pick = [NSMutableArray array];
    NSData *rnd = [MeshCrypto randomBytes:kPairWords * 4]; const uint32_t *r = rnd.bytes;
    for (NSUInteger i = 0; i < kPairWords; i++) [pick addObject:list[r[i] % list.count]];   // 2^32 mod ~2600: Verzerrung < 1e-6
    NSString *words = [pick componentsJoinedByString:@" "];
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSString *tag; NSData *key; derive(words, &tag, &key);
        NSString *sealed = [MeshSeal seal:code key:key context:kPairContext];
        long long now = (long long)[[NSDate date] timeIntervalSince1970];
        dispatch_async(dispatch_get_main_queue(), ^{
            MeshEvent *e = [MeshEvent kind:kPairKind content:sealed ?: @""
                                      tags:@[@[@"d", tag], @[@"expiration", [NSString stringWithFormat:@"%lld", now + kPairValid]]]];
            if (!sealed || ![e signWithKeys:[MeshKeys generate]]) { done(nil, nil, L(@"Could not create the code.")); return; }
            [self.pool publish:e];
            done(words, [NSDate dateWithTimeIntervalSince1970:now + kPairValid], nil);
        });
    });
}

- (void)addContactByWords:(NSString *)input name:(NSString *)name done:(void (^)(NSString *, NSString *))done {
    NSString *words = normalizedWords(input);
    if (!words) { done(nil, L(@"Please enter the 4 words exactly as shown.")); return; }
    if (![self anyRelayConnected]) { done(nil, L(@"Not connected yet. Try again in a moment.")); return; }
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        NSString *tag; NSData *key; derive(words, &tag, &key);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!gPairWait) gPairWait = [NSMutableDictionary dictionary];
            NSString *sub = [@"pair-" stringByAppendingString:[tag substringToIndex:12]];
            gPairWait[sub] = [@{@"events": [NSMutableArray array], @"key": key, @"tag": tag} mutableCopy];
            long long now = (long long)[[NSDate date] timeIntervalSince1970];
            [self.pool subscribe:sub filter:@{@"kinds": @[@(kPairKind)], @"#d": @[tag], @"since": @(now - kPairValid - 60), @"limit": @10}];
            // Antworten der Relays einsammeln: 2 s nach der ersten Karte (falls noch eine zweite kommt), höchstens 8 s
            NSDate *start = [NSDate date];
            __block void (^check)(void);
            void (^decide)(void);
            decide = ^{
                NSMutableDictionary *w = gPairWait[sub]; if (!w) return;
                NSTimeInterval since = -[start timeIntervalSinceNow];
                NSDate *first = w[@"first"];
                if (since < 8 && !(first && -[first timeIntervalSinceNow] >= 2)) { dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), check); return; }
                check = nil;
                [gPairWait removeObjectForKey:sub];
                [self.pool unsubscribe:sub];   // sonst bleibt je Suche ein Abo offen, bis das Relay neue ablehnt
                NSMutableSet *codes = [NSMutableSet set];
                long long t = (long long)[[NSDate date] timeIntervalSince1970];
                for (MeshEvent *e in w[@"events"]) {
                    if (e.kind != kPairKind || ![e hasTag:@"d" value:tag] || t - e.createdAt > kPairValid + 60 || e.createdAt - t > 300) continue;
                    NSString *code = [MeshSeal open:e.content key:key context:kPairContext];
                    if (code.length && [MeshContactCode parse:code]) [codes addObject:code];
                }
                if (codes.count == 0) { done(nil, L(@"No contact found for these words. They may have expired – ask for new ones.")); return; }
                if (codes.count > 1) { done(nil, L(@"These words point to more than one contact. Ask for new words.")); return; }
                NSString *hex = [self addContact:[codes anyObject] name:name];
                done(hex, hex ? nil : L(@"That is your own code."));
            };
            check = decide;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), check);
        });
    });
}

@end

@implementation MeshSession (PairingInternal)
- (void)receivePairingEvent:(MeshEvent *)event subId:(NSString *)subId {
    NSMutableDictionary *w = gPairWait[subId];
    if (w && [w[@"events"] count] < 20) { [w[@"events"] addObject:event]; if (!w[@"first"]) w[@"first"] = [NSDate date]; }
}
@end
