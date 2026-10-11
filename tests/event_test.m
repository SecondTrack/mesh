// Typprüfung empfangener Events und Relay-Nachrichten (nichts darf abstürzen).
#import "MeshTest.h"
#import "MeshEvent.h"
#import "MeshKeys.h"
#import "MeshCrypto.h"
#import "MeshRelay.h"
#import "MeshJSON.h"

static void spin(void) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]]; }

@interface Spy : NSObject <MeshRelayDelegate>
@property int events, oks, auths, eoses;
@end
@implementation Spy
- (void)relay:(MeshRelay *)r didReceiveEvent:(MeshEvent *)e subId:(NSString *)s { self.events++; }
- (void)relay:(MeshRelay *)r didGetOKForEvent:(NSString *)e accepted:(BOOL)a message:(NSString *)m { self.oks++; }
- (void)relay:(MeshRelay *)r didRequestAuth:(NSString *)c { self.auths++; }
- (void)relay:(MeshRelay *)r didFinishStoredEvents:(NSString *)s { self.eoses++; }
@end

static NSDictionary *with(NSDictionary *d, NSString *k, id v) {
    NSMutableDictionary *m = [d mutableCopy]; if (v) m[k] = v; else [m removeObjectForKey:k]; return m;
}

int main(void) { @autoreleasepool {
    MeshKeys *k = [MeshKeys generate];
    MeshEvent *e = [MeshEvent kind:4 content:@"x" tags:@[@[@"p", @"ab"]]];
    [e signWithKeys:k];
    NSDictionary *good = [e toJSONObject];
    MeshEvent *p = [MeshEvent fromJSONObject:good];
    check(p && [p verify], "valid event");

    NSDictionary *cases = @{
        @"id number": with(good, @"id", @42), @"id short": with(good, @"id", @"abcd"),
        @"id upper": with(good, @"id", [good[@"id"] uppercaseString]), @"id missing": with(good, @"id", nil),
        @"pubkey null": with(good, @"pubkey", [NSNull null]), @"sig short": with(good, @"sig", @"00"),
        @"sig array": with(good, @"sig", @[]), @"kind string": with(good, @"kind", @"4"),
        @"kind bool": with(good, @"kind", @YES), @"kind huge": with(good, @"kind", @70000),
        @"kind fraction": with(good, @"kind", @4.5), @"created negative": with(good, @"created_at", @-1),
        @"content number": with(good, @"content", @1), @"content dict": with(good, @"content", @{}),
        @"tags dict": with(good, @"tags", @{}), @"tag number": with(good, @"tags", @[@[@"p", @1]]),
        @"tag flat": with(good, @"tags", @[@"p"]) };
    for (NSString *name in cases) check([MeshEvent fromJSONObject:cases[name]] == nil, name.UTF8String);
    check([MeshEvent fromJSONObject:(id)@[]] == nil, "array instead of object");

    // NIP-01-Serialisierung: genau sieben Zeichen escapen, alles andere roh (auch Steuerzeichen)
    MeshEvent *x = [MeshEvent kind:1 content:@"a\"b\\c\nd\x01e😀" tags:@[@[@"t", @"x\ty"]]];
    x.pubkey = @"ab"; x.createdAt = 7;
    NSString *canon = [x performSelector:@selector(canonical)];
    check([canon isEqualToString:@"[0,\"ab\",7,1,[[\"t\",\"x\\ty\"]],\"a\\\"b\\\\c\\nd\x01e😀\"]"], "NIP-01 escaping");
    // Nicht als UTF-8 darstellbar (halbes Surrogatpaar): nicht signieren
    unichar lone = 0xD83D;
    MeshEvent *broken = [MeshEvent kind:1 content:[NSString stringWithCharacters:&lone length:1] tags:@[]];
    check(![broken signWithKeys:k], "lone surrogate not signed");

    // Relay-Nachrichten
    MeshRelay *r = [[MeshRelay alloc] initWithURL:@"wss://relay.example"];
    Spy *spy = [Spy new]; r.delegate = spy;
    NSString *(^json)(id) = ^(id o) { return [[NSString alloc] initWithData:[MeshJSON dataWithObject:o] encoding:NSUTF8StringEncoding]; };
    NSArray *junk = @[ @"", @"null", @"{}", @"[]", @"[1]", @"[\"EVENT\"]", @"[\"EVENT\",1,{}]",
        json(@[@"EVENT", @"s", @"str"]), json(@[@"EVENT", @"s", with(good, @"kind", @"4")]),
        json(@[@"EOSE", @5]), json(@[@"AUTH", @{}]), json(@[@"AUTH", [@"" stringByPaddingToLength:5000 withString:@"c" startingAtIndex:0]]),
        json(@[@"OK", @1, @YES]), json(@[@"OK", @"id", @"true"]), json(@[@"OK", @"id", @YES, @7]), @"[\"EVENT\",\"s\",{\"id\":" ];
    for (NSString *m in junk) [r performSelector:@selector(handleMessage:) withObject:m];
    spin();
    check(spy.events == 0 && spy.auths == 0 && spy.eoses == 0, "junk ignored");
    check(spy.oks == 1, "OK with non-string message still accepted");

    [r performSelector:@selector(handleMessage:) withObject:json(@[@"EVENT", @"s", good])];
    [r performSelector:@selector(handleMessage:) withObject:json(@[@"EOSE", @"s"])];
    [r performSelector:@selector(handleMessage:) withObject:json(@[@"AUTH", @"challenge"])];
    spin();
    check(spy.events == 1 && spy.eoses == 1 && spy.auths == 1, "valid messages delivered");

    // Verschachtelungsbombe vom Relay: abgelehnt, bevor der System-Parser sie sieht
    NSMutableData *deep = [NSMutableData data];
    for (int i = 0; i < 100000; i++) [deep appendBytes:"[" length:1];
    check([MeshJSON objectWithData:deep] == nil, "deep nesting rejected");
    check([MeshJSON objectWithData:[@"[\"[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[\",1]" dataUsingEncoding:NSUTF8StringEncoding]] != nil,
          "brackets inside strings don't count");
    check([MeshJSON objectWithData:[@"[\"\\\"[\",{\"a\":[1]}]" dataUsingEncoding:NSUTF8StringEncoding]] != nil, "escaped quote handled");
    // Dieselbe Bombe als UTF-16: Nullbytes würden die UTF-8-Zählung aus dem Tritt bringen
    NSMutableData *wide = [NSMutableData dataWithBytes:"\0[\0\"\"\0\0\"\0," length:10];
    for (int i = 0; i < 100000; i++) [wide appendBytes:"\0[" length:2];
    check([MeshJSON objectWithData:wide] == nil, "utf-16 nesting rejected");
    check([MeshJSON objectWithData:[NSData dataWithBytes:"\0[\0]" length:4]] == nil, "raw NUL rejected");

    MeshEvent *dm = [MeshEvent kind:4 content:@"x" tags:@[ @[@"p", @"abc"], @[@"e"] ]];
    check([dm hasTag:@"p" value:@"abc"] && ![dm hasTag:@"p" value:@"abd"] && ![dm hasTag:@"e" value:@""], "tag lookup");

    // Gesperrt: überschriebener Schlüssel signiert und leitet nichts mehr ab
    MeshKeys *gone = [MeshKeys generate];
    [gone wipe];
    check(!gone.seckey && ![gone schnorrSign:[MeshCrypto randomBytes:32]] && ![gone derivedKey:@"mesh-db-v1"]
          && ![gone ecdhSharedX:k.xonlyPub], "wiped keys are unusable");

    return testsDone();
}}
