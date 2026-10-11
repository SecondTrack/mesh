// Notlöschung: Token wie Android (PBKDF2-Vektor aus Pythons hashlib), Codewort per Tag und Text,
// Panik-PIN nur mit passendem Gerätegeheimnis.
#import "MeshTest.h"
#import "MeshPanic.h"

@interface MemoryPanicStorage : NSObject <MeshPanicStorage>
@property (nonatomic) NSMutableDictionary *items;
@end
@implementation MemoryPanicStorage
- (instancetype)init { if ((self = [super init])) _items = [NSMutableDictionary dictionary]; return self; }
- (NSData *)panicDataNamed:(NSString *)name { return _items[name]; }
- (BOOL)setPanicData:(NSData *)data named:(NSString *)name {
    if (data) _items[name] = data; else [_items removeObjectForKey:name];
    return YES;
}
@end

int main(void) { @autoreleasepool {
    NSString *me = [@"" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0];
    NSString *other = [@"" stringByPaddingToLength:64 withString:@"b" startingAtIndex:0];
    // python3: hashlib.pbkdf2_hmac('sha256', 'Rote Möwe 7'.encode(), ('mesh:panic:v2:' + 'a'*64).encode(), 120000, 32)
    NSString *vector = @"p2:252ff79237fc1bb2cc5f62aa98c6cea2d7680a8a2075f4070dbd19be87966f2b";
    check([[MeshPanic triggerFor:@"Rote Möwe 7" target:me] isEqualToString:vector], "token like Android");
    check([[MeshPanic triggerFor:@"  Rote Möwe 7\n" target:me] isEqualToString:vector], "token trims like Android");
    check(![[MeshPanic triggerFor:@"Rote Möwe 7" target:other] isEqualToString:vector], "token bound to target");
    check([MeshPanic triggerFor:@"   " target:me] == nil, "empty codeword");

    MemoryPanicStorage *store = [MemoryPanicStorage new];
    MeshPanic *p = [[MeshPanic alloc] initWithStorage:store];
    check(![p hasCodeword] && ![p matchesTrigger:vector], "nothing set");
    check([p setCodeword:@"Rote Möwe 7" pubkeys:@[other, me]] && [p hasCodeword], "codeword set");
    NSString *stored = [[NSString alloc] initWithData:store.items[@"panic.codeword"] encoding:NSUTF8StringEncoding];
    check([stored rangeOfString:@"Möwe"].location == NSNotFound, "codeword itself not stored");
    check([p matchesTrigger:vector] && ![p matchesTrigger:@"p2:00"] && ![p matchesTrigger:nil], "trigger tag");
    check([p matchesTrigger:[MeshPanic triggerFor:@"Rote Möwe 7" target:other]] && [p codewordIdentities] == 2, "token for every identity");
    check([p matchesTrigger:vector sentAt:time(NULL)] && ![p matchesTrigger:vector sentAt:time(NULL) - 7200], "older trigger is a replay");
    check([p matchesText:@"Rote Möwe 7 " myPubkey:me], "codeword as text");
    check(![p matchesText:@"rote möwe 7" myPubkey:me] && ![p matchesText:@"Hallo" myPubkey:me], "other text");
    check([p setCodeword:@"" pubkeys:@[me]] && ![p hasCodeword], "codeword off");

    NSMutableData *secret = [NSMutableData dataWithLength:32]; arc4random_buf(secret.mutableBytes, 32);
    NSMutableData *otherSecret = [NSMutableData dataWithLength:32]; arc4random_buf(otherSecret.mutableBytes, 32);
    check(![p matchesPin:@"999999" deviceSecret:secret], "no panic pin");
    check([p setPin:@"999999" deviceSecret:secret] && [p hasPin], "panic pin set");
    check([p matchesPin:@"999999" deviceSecret:secret], "panic pin matches");
    check(![p matchesPin:@"999998" deviceSecret:secret] && ![p matchesPin:@"999999" deviceSecret:otherSecret], "wrong pin or device");
    check(![p setPin:@"123456" deviceSecret:[NSData data]], "needs device secret");
    [p clearAll];
    check(![p hasPin] && store.items.count == 0, "cleared");
    return testsDone();
}}
