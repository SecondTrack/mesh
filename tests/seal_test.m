// Datenbank-Verschlüsselung: Rundweg, Kontextbindung, Manipulation, Altformat.
#import "MeshTest.h"
#import "MeshSeal.h"
#import "MeshCrypto.h"
#import "MeshBase64.h"

// Altformat enc1 nachbauen (wie es frühere Versionen geschrieben haben).
static NSString *legacySeal(NSString *plain, NSData *key) {
    NSData *ek = [MeshCrypto hmacSHA256:[@"mesh-seal-enc" dataUsingEncoding:NSUTF8StringEncoding] key:key];
    NSData *mk = [MeshCrypto hmacSHA256:[@"mesh-seal-mac" dataUsingEncoding:NSUTF8StringEncoding] key:key];
    NSData *iv = [MeshCrypto randomBytes:16];
    NSMutableData *box = [iv mutableCopy];
    [box appendData:[MeshCrypto aes256cbcEncrypt:[plain dataUsingEncoding:NSUTF8StringEncoding] key:ek iv:iv]];
    [box appendData:[MeshCrypto hmacSHA256:box key:mk]];
    return [@"enc1:" stringByAppendingString:[MeshBase64 encode:box]];
}

int main(void) { @autoreleasepool {
    NSData *key = [MeshCrypto randomBytes:32], *other = [MeshCrypto randomBytes:32];
    NSArray *samples = @[ @"", @"hallo", @"Grüße 👋 aus Köln", [@"" stringByPaddingToLength:200000 withString:@"x" startingAtIndex:0] ];
    for (NSString *s in samples) {
        NSString *sealed = [MeshSeal seal:s key:key context:@"t.c|1"];
        check([MeshSeal isSealed:sealed] && [[MeshSeal open:sealed key:key context:@"t.c|1"] isEqualToString:s], "roundtrip");
    }
    NSString *a = [MeshSeal seal:@"geheim" key:key context:@"contacts.name|aa"];
    check(![a isEqualToString:[MeshSeal seal:@"geheim" key:key context:@"contacts.name|aa"]], "random IV");
    check([a rangeOfString:@"geheim"].location == NSNotFound, "no plaintext inside");
    check([MeshSeal open:a key:other context:@"contacts.name|aa"] == nil, "wrong key");
    check([MeshSeal open:a key:key context:@"contacts.pic|aa"] == nil, "other column refused");
    check([MeshSeal open:a key:key context:@"contacts.name|bb"] == nil, "other row refused");
    check([MeshSeal open:a key:key context:@"contacts.name|a"] == nil, "context prefix refused");
    check([MeshSeal seal:@"x" key:nil context:@"c"] == nil && [MeshSeal seal:@"x" key:[NSData data] context:@"c"] == nil, "no key, no seal");
    unichar lone = 0xD800;
    check([MeshSeal seal:[NSString stringWithCharacters:&lone length:1] key:key context:@"c"] == nil, "no UTF-8, no seal");
    check([MeshSeal open:@"klartext" key:key context:@"c"] == nil && ![MeshSeal isSealed:@"klartext"], "plaintext not sealed");

    // Jedes einzelne gekippte Bit im Container muss erkannt werden
    NSData *box = [MeshBase64 decode:[a substringFromIndex:5]];
    int caught = 0;
    for (NSUInteger i = 0; i < box.length * 8; i++) {
        NSMutableData *m = [box mutableCopy]; ((uint8_t *)m.mutableBytes)[i / 8] ^= 1 << (i % 8);
        if (![MeshSeal open:[@"enc2:" stringByAppendingString:[MeshBase64 encode:m]] key:key context:@"contacts.name|aa"]) caught++;
    }
    check(caught == (int)box.length * 8, "every bit flip detected");
    check([MeshSeal open:@"enc2:" key:key context:@"c"] == nil && [MeshSeal open:@"enc2:!!!" key:key context:@"c"] == nil, "garbage");

    // Altformat: nur über openLegacy, nicht über open
    NSString *old = legacySeal(@"alter wert", key);
    check([MeshSeal isLegacySealed:old] && [[MeshSeal openLegacy:old key:key] isEqualToString:@"alter wert"], "legacy readable");
    check([MeshSeal open:old key:key context:@"c"] == nil, "legacy not accepted as current");
    check([MeshSeal openLegacy:old key:other] == nil, "legacy wrong key");

    return testsDone();
}}
