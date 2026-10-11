// Handshake und Frame-Parser gegen ein bösartiges Relay.
#import "MeshTest.h"
#import "MeshWebSocket.h"
#import "MeshTLSFake.h"
#import "MeshBase64.h"
#import "MeshCrypto.h"

static NSString *acceptFor(NSData *request) {
    NSString *req = [[NSString alloc] initWithData:request encoding:NSUTF8StringEncoding];
    NSRange r = [req rangeOfString:@"Sec-WebSocket-Key: "];
    NSString *key = [[req substringFromIndex:NSMaxRange(r)] componentsSeparatedByString:@"\r\n"][0];
    NSData *h = [MeshCrypto sha1:[[key stringByAppendingString:@"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"]
                                  dataUsingEncoding:NSUTF8StringEncoding]];
    return [MeshBase64 encode:h];
}

// Verbindet mit einem Server, der `status`/`extra` antwortet; accept=NO schickt einen falschen Schlüssel.
static MeshWebSocket *connectWS(NSString *status, NSString *extra, BOOL accept, BOOL *connected) {
    MeshWebSocket *ws = [[MeshWebSocket alloc] init];
    MeshTLS *tls = [ws valueForKey:@"tls"];
    [tls setResponder:^NSData *(NSData *w) {
        NSString *a = accept ? acceptFor(w) : @"AAAAAAAAAAAAAAAAAAAAAAAAAAA=";
        return [[NSString stringWithFormat:@"%@\r\nUpgrade: websocket\r\nSec-WebSocket-Accept: %@\r\n%@\r\n",
                 status, a, extra ?: @""] dataUsingEncoding:NSUTF8StringEncoding];
    }];
    *connected = [ws connectHost:@"relay.example" port:443 path:@"/" error:NULL];
    return ws;
}

static NSData *frame(uint8_t b0, uint64_t len, BOOL lenOnly, NSData *payload, int lenBytes) {
    NSMutableData *f = [NSMutableData dataWithBytes:&b0 length:1];
    if (lenBytes == 0) { uint8_t b = (uint8_t)len; [f appendBytes:&b length:1]; }
    else if (lenBytes == 2) { uint8_t b[3] = {126, len >> 8, len & 0xFF}; [f appendBytes:b length:3]; }
    else { uint8_t b[9] = {127}; for (int i = 0; i < 8; i++) b[1+i] = (len >> (8*(7-i))) & 0xFF; [f appendBytes:b length:9]; }
    if (!lenOnly) [f appendData:payload];
    return f;
}
static NSData *text(NSString *s) {
    NSData *p = [s dataUsingEncoding:NSUTF8StringEncoding];
    return frame(0x81, p.length, NO, p, p.length < 126 ? 0 : (p.length < 65536 ? 2 : 8));
}

int main(void) { @autoreleasepool {
    BOOL up;
    // Handshake
    connectWS(@"HTTP/1.1 101 Switching Protocols", nil, YES, &up);      check(up, "handshake ok");
    connectWS(@"HTTP/1.1 101 Switching Protocols", nil, NO, &up);       check(!up, "wrong accept rejected");
    MeshWebSocket *refused = connectWS(@"HTTP/1.1 200 OK", nil, YES, &up);
    check(!up, "status 200 rejected");
    check(![[refused valueForKey:@"tls"] isOpen], "socket released after failed handshake");
    connectWS(@"HTTP/1.0 418 x 101", nil, YES, &up);                    check(!up, "101 elsewhere rejected");
    NSString *longLine = [@"X-Big: " stringByPaddingToLength:9000 withString:@"a" startingAtIndex:0];
    connectWS(@"HTTP/1.1 101 OK", [longLine stringByAppendingString:@"\r\n"], YES, &up); check(!up, "long header rejected");
    NSMutableString *many = [NSMutableString string]; for (int i = 0; i < 100; i++) [many appendString:@"X-A: b\r\n"];
    connectWS(@"HTTP/1.1 101 OK", many, YES, &up);                      check(!up, "header flood rejected");

    // Frames
    #define WS() ({ MeshWebSocket *w = connectWS(@"HTTP/1.1 101 OK", nil, YES, &up); tls = [w valueForKey:@"tls"]; w; })
    MeshTLS *tls; MeshWebSocket *ws;

    ws = WS(); [tls feed:text(@"[\"EOSE\",\"x\"]")];
    check([[ws readText] isEqualToString:@"[\"EOSE\",\"x\"]"], "short text");
    NSString *mid = [@"" stringByPaddingToLength:300 withString:@"m" startingAtIndex:0];
    NSString *big = [@"" stringByPaddingToLength:70000 withString:@"b" startingAtIndex:0];
    ws = WS(); [tls feed:text(mid)]; [tls feed:text(big)];
    check([[ws readText] isEqualToString:mid] && [[ws readText] isEqualToString:big], "16- and 64-bit lengths");

    ws = WS();
    [tls feed:frame(0x01, 3, NO, [@"abc" dataUsingEncoding:NSUTF8StringEncoding], 0)];
    [tls feed:frame(0x89, 2, NO, [@"hi" dataUsingEncoding:NSUTF8StringEncoding], 0)];   // Ping zwischen Fragmenten
    [tls feed:frame(0x80, 3, NO, [@"def" dataUsingEncoding:NSUTF8StringEncoding], 0)];
    NSUInteger before = tls.written.length;
    check([[ws readText] isEqualToString:@"abcdef"], "fragmented message");
    const uint8_t *w = (const uint8_t *)tls.written.bytes + before;
    check(tls.written.length > before && w[0] == 0x8A, "ping answered with pong");

    // Angriffe: dürfen nicht abstürzen, Verbindung wird beendet
    ws = WS(); [tls feed:frame(0x81, 0x100000004ULL, NO, [@"AAAA" dataUsingEncoding:NSUTF8StringEncoding], 8)];
    check([ws readText] == nil, "2^32+4 length (old heap overflow)");
    ws = WS(); [tls feed:frame(0x81, 0xFFFFFFFFFFFFFFFFULL, YES, nil, 8)];
    check([ws readText] == nil, "2^64-1 length");
    ws = WS(); [tls feed:frame(0x81, 5 * 1024 * 1024, NO, [NSMutableData dataWithLength:5 * 1024 * 1024], 8)];
    check([ws readText] == nil, "5 MB message refused");
    ws = WS(); NSData *chunk = [NSMutableData dataWithLength:60000];
    for (int i = 0; i < 80; i++) [tls feed:frame((i ? 0x00 : 0x01) | (i == 79 ? 0x80 : 0), chunk.length, NO, chunk, 2)];
    check([ws readText] == nil, "fragment flood over 4 MB");
    ws = WS(); NSMutableData *m = [NSMutableData dataWithBytes:"\x81\x83\x01\x02\x03\x04" "abc" length:10];
    [tls feed:m]; check([ws readText] == nil, "masked server frame");
    ws = WS(); [tls feed:frame(0x89, 126, NO, [NSMutableData dataWithLength:126], 2)];
    check([ws readText] == nil, "oversized ping");
    ws = WS(); [tls feed:frame(0x09, 1, NO, [NSData dataWithBytes:"x" length:1], 0)];
    check([ws readText] == nil, "fragmented control frame");
    ws = WS(); [tls feed:frame(0x83, 1, NO, [NSData dataWithBytes:"x" length:1], 0)];
    check([ws readText] == nil, "unknown opcode");
    ws = WS(); [tls feed:frame(0xC1, 1, NO, [NSData dataWithBytes:"x" length:1], 0)];
    check([ws readText] == nil, "reserved bits");
    ws = WS(); [tls feed:frame(0x81, 2, NO, [NSData dataWithBytes:"\xff\xfe" length:2], 0)];
    check([ws readText] == nil, "invalid UTF-8");
    ws = WS(); [tls feed:frame(0x80, 1, NO, [NSData dataWithBytes:"x" length:1], 0)];
    check([ws readText] == nil, "continuation without start");
    ws = WS(); [tls feed:frame(0x01, 1, NO, [NSData dataWithBytes:"a" length:1], 0)];
    [tls feed:frame(0x81, 1, NO, [NSData dataWithBytes:"b" length:1], 0)];
    check([ws readText] == nil, "new text frame inside fragmentation");
    ws = WS(); [tls feed:frame(0x88, 0, NO, [NSData data], 0)];
    check([ws readText] == nil, "close frame");

    return testsDone();
}}
