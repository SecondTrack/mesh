// scrypt gegen RFC 7914, Abschnitt 12 (gleiche Werte liefert Pythons hashlib.scrypt/OpenSSL).
#import "MeshTest.h"
#import "MeshScrypt.h"
#import "MeshHex.h"

static NSString *run(NSString *pw, NSString *salt, uint32_t N, uint32_t r, uint32_t p) {
    return [MeshHex encode:MeshScrypt([pw dataUsingEncoding:NSUTF8StringEncoding], [salt dataUsingEncoding:NSUTF8StringEncoding], N, r, p, 64)];
}

int main(void) { @autoreleasepool {
    check([run(@"", @"", 16, 1, 1) isEqualToString:@"77d6576238657b203b19ca42c18a0497f16b4844e3074ae8dfdffa3fede21442fcd0069ded0948f8326a753a0fc81f17e8d3e0fb2e0d3628cf35e20c38d18906"], "RFC 7914 #1");
    check([run(@"password", @"NaCl", 1024, 8, 16) isEqualToString:@"fdbabe1c9d3472007856e7190d01e9fe7c6ad7cbc8237830e77376634b3731622eaf30d92e22a3886ff109279d9830dac727afb94a83ee6d8360cbdfa2cc0640"], "RFC 7914 #2");
    check([run(@"pleaseletmein", @"SodiumChloride", 16384, 8, 1) isEqualToString:@"7023bdcb3afd7348461c06cd81fd38ebfda8fbba904f8e3ea9b543f6545da1f2d5432955613f0fcf62d49705242a9af9e61e85dc0d651e40dfcf017b45575887"], "RFC 7914 #3");
    check(MeshScrypt([NSData data], [NSData data], 1000, 8, 1, 32) == nil, "N must be a power of two");
    return testsDone();
}}
