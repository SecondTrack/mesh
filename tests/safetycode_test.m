// QR-Abgleich des Sicherheits-Codes; gleiche Fälle und gleiches Format wie SafetyCodeTest auf Android.
#import "MeshTest.h"
#import "MeshSafetyCode.h"

static NSString *rep(NSString *c) { return [@"" stringByPaddingToLength:64 withString:c startingAtIndex:0]; }

int main(void) { @autoreleasepool {
    NSString *a = rep(@"a"), *b = rep(@"b"), *c = rep(@"c");
    NSArray *sn = @[@"12345", @"67890", @"11111", @"22222", @"33333", @"44444", @"55555", @"66666", @"77777", @"88888", @"99999", @"00000"];
    NSString *shownByB = [MeshSafetyCode payloadFrom:b to:a groups:sn];
    NSString *expect = [NSString stringWithFormat:@"meshsn:1:%@:%@:123456789011111222223333344444555556666677777888889999900000", b, a];
    check([shownByB isEqualToString:expect], "format wie Android");
    check([MeshSafetyCode check:shownByB me:a peer:b groups:sn] == MeshSafetyMatch, "match");

    NSMutableArray *other = [sn mutableCopy]; other[0] = @"12346";
    check([MeshSafetyCode check:[MeshSafetyCode payloadFrom:b to:a groups:other] me:a peer:b groups:sn] == MeshSafetyMismatch, "mismatch");

    check([MeshSafetyCode check:[MeshSafetyCode payloadFrom:c to:a groups:sn] me:a peer:b groups:sn] == MeshSafetyOtherContact, "anderer Absender");
    check([MeshSafetyCode check:[MeshSafetyCode payloadFrom:b to:c groups:sn] me:a peer:b groups:sn] == MeshSafetyOtherContact, "anderer Empfänger");
    check([MeshSafetyCode check:[MeshSafetyCode payloadFrom:a to:b groups:sn] me:a peer:b groups:sn] == MeshSafetyOtherContact, "eigener Code");

    check([MeshSafetyCode check:@"mesh:npub1xyz" me:a peer:b groups:sn] == MeshSafetyNotACode, "kein Code");
    check([MeshSafetyCode check:[NSString stringWithFormat:@"meshsn:1:%@:%@:123", b, a] me:a peer:b groups:sn] == MeshSafetyNotACode, "zu kurz");
    NSString *upper = [@"  meshsn:1:" stringByAppendingFormat:@"%@:%@:%@\n", b.uppercaseString, a.uppercaseString, [sn componentsJoinedByString:@""]];
    check([MeshSafetyCode check:upper me:a peer:b groups:sn] == MeshSafetyMatch, "Groß/Leerraum egal");
    return testsDone();
}}
