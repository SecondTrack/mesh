// MeshBase64 gegen RFC-4648-Testvektoren und die Foundation-Implementierung.
#import "MeshTest.h"
#import "MeshBase64.h"

int main(void) { @autoreleasepool {
    // RFC 4648 §10
    NSArray *vec = @[ @[@"", @""], @[@"f", @"Zg=="], @[@"fo", @"Zm8="], @[@"foo", @"Zm9v"],
                      @[@"foob", @"Zm9vYg=="], @[@"fooba", @"Zm9vYmE="], @[@"foobar", @"Zm9vYmFy"] ];
    for (NSArray *v in vec) {
        NSData *raw = [v[0] dataUsingEncoding:NSUTF8StringEncoding];
        check([[MeshBase64 encode:raw] isEqualToString:v[1]], "RFC 4648 encode");
        check([[MeshBase64 decode:v[1]] isEqual:raw], "RFC 4648 decode");
    }
    // Zeilenumbrüche im Eingabetext werden übersprungen
    check([[MeshBase64 decode:@"Zm9v\r\nYmFy"] isEqual:[@"foobar" dataUsingEncoding:NSUTF8StringEncoding]], "whitespace");
    // Zufallsdaten: gleiches Ergebnis wie Foundation, Hin- und Rückweg verlustfrei
    for (int i = 0; i < 2000; i++) {
        NSMutableData *d = [NSMutableData dataWithLength:arc4random_uniform(300)];
        arc4random_buf(d.mutableBytes, d.length);
        NSString *e = [MeshBase64 encode:d];
        check([e isEqualToString:[d base64EncodedStringWithOptions:0]], "matches Foundation");
        check([[MeshBase64 decode:e] isEqual:d], "roundtrip");
    }
    return testsDone();
}}
