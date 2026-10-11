// BIP-173-Testvektoren und Eingaben, die früher den Stack überschrieben.
#import "MeshTest.h"
#import "MeshBech32.h"
#import "MeshHex.h"

int main(void) { @autoreleasepool {
    // BIP-173 gültig (Prüfsumme)
    NSArray *valid = @[ @"A12UEL5L", @"a12uel5l",
        @"an83characterlonghumanreadablepartthatcontainsthenumber1andtheexcludedcharactersbio1tt5tgs",
        @"abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw",
        @"11qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqc8247j",
        @"split1checkupstagehandshakeupstreamerranterredcaperred2y9e3w" ];
    for (NSString *v in valid) { NSString *h; check([MeshBech32 decode:v hrp:&h] != nil, v.UTF8String); }

    // BIP-173 ungültig
    NSArray *invalid = @[ [NSString stringWithFormat:@"%c1nwldj5", 0x20], [NSString stringWithFormat:@"%c1axkwrx", 0x7f],
        [NSString stringWithFormat:@"%C1eym55h", (unichar)0x80],
        @"an84characterslonghumanreadablepartthatcontainsthenumber1andtheexcludedcharactersbio1569pvx",
        @"pzry9x0s0muk", @"1pzry9x0s0muk", @"x1b4n0q5v", @"li1dgmt3", [NSString stringWithFormat:@"de1lg7wt%C", (unichar)0xff],
        @"A1G7SGD8", @"10a06t8", @"1qzzfhee", @"A12uEL5L" ];
    for (NSString *v in invalid) check([MeshBech32 decode:v hrp:NULL] == nil, "BIP-173 invalid");

    // npub-Rundweg (NIP-19-Vektor)
    NSData *pk = [MeshHex decode:@"3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"];
    NSString *npub = [MeshBech32 encodeHrp:@"npub" data:pk];
    check([npub isEqualToString:@"npub180cvv07tjdrrgpa0j7j7tmnyl2yr6yr7l8j4s3evf6u64th6gkwsyjh6w6"], "NIP-19 encode");
    NSString *hrp; check([[MeshBech32 decode:npub hrp:&hrp] isEqual:pk] && [hrp isEqualToString:@"npub"], "NIP-19 decode");

    // Angriffe: langes Präfix (früher Stack-Überlauf in chkin[512]), riesige Eingaben
    NSString *longHrp = [[@"" stringByPaddingToLength:5000 withString:@"a" startingAtIndex:0] stringByAppendingString:@"1qqqqqq"];
    check([MeshBech32 decode:longHrp hrp:NULL] == nil, "5000-char hrp");
    NSString *huge = [@"npub1" stringByPaddingToLength:100000 withString:@"q" startingAtIndex:0];
    check([MeshBech32 decode:huge hrp:NULL] == nil, "100k data part");
    check([MeshBech32 decode:@"npüb1qqqqqqqqqqqqqq" hrp:NULL] == nil, "non-ASCII");
    check([MeshBech32 decode:@"" hrp:NULL] == nil, "empty");
    check([MeshBech32 encodeHrp:[@"" stringByPaddingToLength:300 withString:@"x" startingAtIndex:0] data:pk] == nil, "encode long hrp");
    check([MeshBech32 encodeHrp:@"npub" data:[NSMutableData dataWithLength:100]] == nil, "encode too much data");

    return testsDone();
}}
