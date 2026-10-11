// Eigene PBKDF2-Umsetzung gegen CommonCrypto und RFC-7914-Testvektor.
#import "MeshTest.h"
#import <CommonCrypto/CommonKeyDerivation.h>
#import "MeshCrypto.h"
#import "MeshHex.h"

static NSData *cc(NSData *pw, NSData *salt, int it) {
    NSMutableData *o = [NSMutableData dataWithLength:32];
    CCKeyDerivationPBKDF(kCCPBKDF2, pw.bytes, pw.length, salt.bytes, salt.length, kCCPRFHmacAlgSHA256, it, o.mutableBytes, 32);
    return o;
}

int main(void) { @autoreleasepool {
    // RFC 7914 §11: PBKDF2-HMAC-SHA256 P="passwd", S="salt", c=1 → 55ac046e56e3089f…
    NSData *v = MeshPBKDF2SHA256Portable([@"passwd" dataUsingEncoding:NSUTF8StringEncoding],
                                         [@"salt" dataUsingEncoding:NSUTF8StringEncoding], 1);
    check([[MeshHex encode:v] hasPrefix:@"55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc"], "RFC 7914 vector");
    // Bitgleich zu CommonCrypto: PIN-artige Eingaben, echte Iterationszahl, Zufalls-Salts
    int iters[] = { 1, 2, 1000, 40000 };
    for (int i = 0; i < 4; i++) for (int k = 0; k < 6; k++) {
        NSData *pw = [[NSString stringWithFormat:@"%06d", (int)arc4random_uniform(1000000)] dataUsingEncoding:NSUTF8StringEncoding];
        NSData *salt = [MeshCrypto randomBytes:16];
        check([MeshPBKDF2SHA256Portable(pw, salt, iters[i]) isEqual:cc(pw, salt, iters[i])], "matches CommonCrypto");
    }
    // Öffentliche Methode (nutzt auf dem Mac die Systemfunktion) liefert dasselbe
    NSData *salt = [MeshCrypto randomBytes:16];
    check([[MeshCrypto pbkdf2:@"123456" salt:salt iters:40000] isEqual:MeshPBKDF2SHA256Portable([@"123456" dataUsingEncoding:NSUTF8StringEncoding], salt, 40000)], "pbkdf2: == portable");
    return testsDone();
}}
