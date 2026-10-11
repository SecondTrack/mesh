// MeshJSONCodec gegen NSJSONSerialization (macOS). Aufruf: tests/run.sh
#import "MeshTest.h"
#import "MeshJSONCodec.h"

int main(void) { @autoreleasepool {
    NSArray *valid = @[
        @"[\"EVENT\",\"sub1\",{\"id\":\"ab12\",\"kind\":4,\"tags\":[[\"p\",\"ff00\"]],\"content\":\"hi?iv=x\",\"created_at\":1728370000}]",
        @"{\"name\":\"J\\u00fcrgen \\ud83d\\ude00\",\"about\":\"Zeile1\\nZeile2\\t\\\"zitat\\\" \\\\ /\"}",
        @"[0,-1,1.5,-2.25e3,1E-7,123456789012345,true,false,null,\"\",[],{}]",
        @"  {\"a\" : [ 1 , { \"b\" : \"ü€😀\" } ] }  ",
        @"[\"OK\",\"e1\",true,\"\"]", @"[\"EOSE\",\"s\"]", @"[\"NOTICE\",\"rate-limited\"]",
    ];
    for (NSString *s in valid) {
        NSData *d = [s dataUsingEncoding:NSUTF8StringEncoding];
        id mine = [MeshJSONCodec objectWithData:d];
        id sys  = [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL];
        check(mine && [mine isEqual:sys], [@"parse " stringByAppendingString:s].UTF8String);
        // Rundlauf: serialisieren mit uns, parsen mit Apple → gleiches Objekt
        NSData *out = [MeshJSONCodec dataWithObject:mine];
        id back = out ? [NSJSONSerialization JSONObjectWithData:out options:0 error:NULL] : nil;
        check(back && [back isEqual:sys], [@"roundtrip " stringByAppendingString:s].UTF8String);
    }
    // Booleans bleiben Booleans (nicht 1/0)
    NSData *b = [MeshJSONCodec dataWithObject:@[@YES, @NO, @1, @0]];
    check([[[NSString alloc] initWithData:b encoding:NSUTF8StringEncoding] isEqualToString:@"[true,false,1,0]"], "bool vs int");

    NSArray *invalid = @[ @"", @"[", @"]", @"{\"a\":}", @"[1,]", @"{\"a\":1,}", @"[01]", @"[1.]", @"[.5]", @"[-]",
        @"[\"\\x\"]", @"[\"\\ud83d\"]", @"[\"\\udc00\"]", @"[\"a", @"[\"tab\there\"]", @"[tru]", @"[nul]",
        @"{1:2}", @"[1] x", @"[1][2]", @"{\"a\" 1}", @"NaN", @"[Infinity]" ];
    for (NSString *s in invalid)
        check([MeshJSONCodec objectWithData:[s dataUsingEncoding:NSUTF8StringEncoding]] == nil, [@"reject " stringByAppendingString:s].UTF8String);

    // Bösartige Eingaben: tiefe Verschachtelung, Riesen-Dokument, ungültiges UTF-8
    NSMutableString *deep = [NSMutableString string];
    for (int i = 0; i < 100000; i++) [deep appendString:@"["];
    check([MeshJSONCodec objectWithData:[deep dataUsingEncoding:NSUTF8StringEncoding]] == nil, "reject depth 100000 (kein Stack-Überlauf)");
    NSMutableString *d64 = [NSMutableString string]; for (int i = 0; i < 64; i++) [d64 appendString:@"["]; for (int i = 0; i < 64; i++) [d64 appendString:@"]"];
    check([MeshJSONCodec objectWithData:[d64 dataUsingEncoding:NSUTF8StringEncoding]] != nil, "accept depth 64");
    NSMutableData *huge = [NSMutableData dataWithLength:MeshJSONMaxBytes + 1];
    check([MeshJSONCodec objectWithData:huge] == nil, "reject > max size");
    const uint8_t badutf[] = { '[', '"', 0xC3, 0x28, '"', ']' };
    check([MeshJSONCodec objectWithData:[NSData dataWithBytes:badutf length:sizeof badutf]] == nil, "reject invalid UTF-8");
    check([MeshJSONCodec dataWithObject:@[[NSDate date]]] == nil, "reject unsupported type");
    check([MeshJSONCodec dataWithObject:@[@(NAN)]] == nil, "reject NaN");

    // Zufalls-Fuzz: darf nie abstürzen und muss mit Apple übereinstimmen, wenn beide parsen
    srandom(42); int agree = 0;
    const char alphabet[] = "[]{}\",:01-.eE \\u\"tfn";
    for (int i = 0; i < 20000; i++) {
        int n = 1 + (int)(random() % 24); char buf[32];
        for (int k = 0; k < n; k++) buf[k] = alphabet[random() % (sizeof alphabet - 1)];
        NSData *d = [NSData dataWithBytes:buf length:n];
        id m = [MeshJSONCodec objectWithData:d], s = [NSJSONSerialization JSONObjectWithData:d options:NSJSONReadingAllowFragments error:NULL];
        if (m && (!s || ![m isEqual:s])) { bad++; printf("  FAIL fuzz %.*s\n", n, buf); }
        else agree++;
    }
    check(agree == 20000, "fuzz 20000");
    return testsDone();
}}
