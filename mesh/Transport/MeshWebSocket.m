#import "MeshWebSocket.h"
#import "MeshBase64.h"
#import "MeshTLS.h"
#import "MeshCrypto.h"

// Obergrenzen gegen bösartige Relays: größte Nachricht (Sprachnachricht mit Base64 und JSON
// bleibt deutlich darunter), längste Header-Zeile, Anzahl Header-Zeilen.
static const uint64_t kMaxMessage = 4 * 1024 * 1024;
static const NSUInteger kMaxHeaderLine = 8192, kMaxHeaderLines = 64;

@implementation MeshWebSocket {
    MeshTLS *_tls;
    NSMutableData *_rx;   // Lesepuffer über TLS-Reads
    BOOL _closed;
}

- (instancetype)init {
    if ((self = [super init])) { _tls = [[MeshTLS alloc] init]; _rx = [NSMutableData data]; }
    return self;
}

#pragma mark - Low-level buffered read

// Genau n Bytes aus dem Puffer/TLS liefern. nil bei Close.
- (NSData *)readExactly:(NSUInteger)n {
    while (_rx.length < n) {
        NSData *chunk = [_tls readUpTo:8192];
        if (!chunk) return nil;
        [_rx appendData:chunk];
    }
    NSData *out = [_rx subdataWithRange:NSMakeRange(0, n)];
    [_rx replaceBytesInRange:NSMakeRange(0, n) withBytes:NULL length:0];
    return out;
}

// Eine Zeile (bis \r\n) für den HTTP-Handshake. nil bei Close oder überlanger Zeile.
- (NSString *)readHttpLine {
    NSMutableData *line = [NSMutableData data];
    while (1) {
        NSData *b = [self readExactly:1];
        if (!b || line.length >= kMaxHeaderLine) return nil;
        const char c = *(const char *)b.bytes;
        if (c == '\n') break;
        if (c != '\r') [line appendData:b];
    }
    return [[NSString alloc] initWithData:line encoding:NSUTF8StringEncoding];
}

#pragma mark - Handshake

// Scheitert der Handshake, wird der Socket sofort freigegeben.
- (BOOL)connectHost:(NSString *)host port:(int)port path:(NSString *)path error:(NSString **)err {
    if ([self handshakeHost:host port:port path:path error:err]) return YES;
    @synchronized (self) { _closed = YES; }
    [_tls close];
    return NO;
}

- (BOOL)handshakeHost:(NSString *)host port:(int)port path:(NSString *)path error:(NSString **)err {
    if (![_tls connectHost:host port:port error:err]) return NO;

    NSData *keyBytes = [MeshCrypto randomBytes:16];
    NSString *wsKey = [MeshBase64 encode:keyBytes];
    NSString *req = [NSString stringWithFormat:
        @"GET %@ HTTP/1.1\r\n"
        @"Host: %@\r\n"
        @"Upgrade: websocket\r\n"
        @"Connection: Upgrade\r\n"
        @"Sec-WebSocket-Key: %@\r\n"
        @"Sec-WebSocket-Version: 13\r\n"
        @"\r\n", path.length ? path : @"/", host, wsKey];
    if ([_tls write:[req dataUsingEncoding:NSUTF8StringEncoding]] < 0) return NO;

    NSString *status = [self readHttpLine];
    if (![status hasPrefix:@"HTTP/1.1 101"]) {
        if (err) *err = [NSString stringWithFormat:@"WS-Handshake: %@", status ?: @"(keine Antwort)"];
        return NO;
    }
    // Header bis zur Leerzeile; Sec-WebSocket-Accept muss zu unserem Schlüssel passen (RFC 6455 §4.1).
    NSString *expected = [MeshBase64 encode:[MeshCrypto sha1:[[wsKey stringByAppendingString:
                          @"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"] dataUsingEncoding:NSUTF8StringEncoding]]];
    BOOL accepted = NO;
    for (NSUInteger i = 0; ; i++) {
        NSString *h = [self readHttpLine];
        if (!h || i >= kMaxHeaderLines) { if (err) *err = @"WS-Handshake: Header ungültig"; return NO; }
        if (!h.length) break;
        NSRange c = [h rangeOfString:@":"];
        if (c.location == NSNotFound) continue;
        NSString *name = [[h substringToIndex:c.location] lowercaseString];
        NSString *value = [[h substringFromIndex:c.location + 1]
                           stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([name isEqualToString:@"sec-websocket-accept"]) accepted = [value isEqualToString:expected];
    }
    if (!accepted) { if (err) *err = @"WS-Handshake: Accept-Schlüssel falsch"; return NO; }
    return YES;
}

#pragma mark - Frames

- (BOOL)sendFrame:(uint8_t)opcode payload:(NSData *)payload {
    NSMutableData *f = [NSMutableData data];
    uint8_t b0 = 0x80 | opcode;               // FIN + opcode
    [f appendBytes:&b0 length:1];

    NSUInteger len = payload.length;
    uint8_t maskBit = 0x80;                    // Clients maskieren immer (RFC 6455)
    if (len < 126) {
        uint8_t b1 = maskBit | (uint8_t)len; [f appendBytes:&b1 length:1];
    } else if (len < 65536) {
        uint8_t b1 = maskBit | 126; [f appendBytes:&b1 length:1];
        uint8_t ex[2] = { (len >> 8) & 0xFF, len & 0xFF }; [f appendBytes:ex length:2];
    } else {
        uint8_t b1 = maskBit | 127; [f appendBytes:&b1 length:1];
        uint8_t ex[8]; for (int i = 0; i < 8; i++) ex[i] = (len >> (8 * (7 - i))) & 0xFF;
        [f appendBytes:ex length:8];
    }
    NSData *mask = [MeshCrypto randomBytes:4];
    [f appendData:mask];
    const uint8_t *m = mask.bytes;
    const uint8_t *p = payload.bytes;
    NSMutableData *masked = [NSMutableData dataWithLength:len];
    uint8_t *out = masked.mutableBytes;
    for (NSUInteger i = 0; i < len; i++) out[i] = p[i] ^ m[i % 4];
    [f appendData:masked];

    return [_tls write:f] >= 0;
}

- (BOOL)sendText:(NSString *)text {
    if (_closed) return NO;
    return [self sendFrame:0x1 payload:[text dataUsingEncoding:NSUTF8StringEncoding]];
}

// Nächste vollständige Text-Nachricht. Protokollverstöße und überlange Nachrichten
// beenden die Verbindung (nil), statt Speicher anzufordern, den ein Relay frei wählen könnte.
- (NSString *)readText {
    NSMutableData *msg = [NSMutableData data];
    BOOL fragmented = NO;   // innerhalb einer Nachricht aus mehreren Frames
    while (1) {
        NSData *hdr = [self readExactly:2];
        if (!hdr) return nil;
        const uint8_t *b = hdr.bytes;
        BOOL fin = (b[0] & 0x80) != 0;
        uint8_t opcode = b[0] & 0x0F;
        BOOL masked = (b[1] & 0x80) != 0;
        uint64_t len = b[1] & 0x7F;

        if (len == 126) {
            NSData *e = [self readExactly:2]; if (!e) return nil;
            const uint8_t *x = e.bytes; len = ((uint64_t)x[0] << 8) | x[1];
        } else if (len == 127) {
            NSData *e = [self readExactly:8]; if (!e) return nil;
            const uint8_t *x = e.bytes; len = 0;
            for (int i = 0; i < 8; i++) len = (len << 8) | x[i];
        }
        BOOL control = (opcode & 0x8) != 0;
        if (masked                                          // Server darf nicht maskieren
            || (b[0] & 0x70)                                // keine Extensions ausgehandelt
            || (control && (len > 125 || !fin))             // Steuer-Frames: klein, nicht fragmentiert
            || len > kMaxMessage - msg.length) {            // Gesamtgröße inkl. Fragmente
            [self close];
            return nil;
        }

        NSData *payload = len ? [self readExactly:(NSUInteger)len] : [NSData data];
        if (!payload) return nil;

        switch (opcode) {
            case 0x8: [self close]; return nil;                       // close
            case 0x9: [self sendFrame:0xA payload:payload]; break;    // ping -> pong
            case 0xA: break;                                          // pong
            case 0x0: case 0x1: case 0x2: {                           // continuation/text/binary
                // Fortsetzung nur innerhalb einer Fragmentierung, neue Nachricht nur außerhalb.
                if ((opcode == 0x0) != fragmented) { [self close]; return nil; }
                [msg appendData:payload];
                fragmented = !fin;
                if (fragmented) break;
                NSString *text = [[NSString alloc] initWithData:msg encoding:NSUTF8StringEncoding];
                if (!text) [self close];                             // ungültiges UTF-8
                return text;
            }
            default: [self close]; return nil;                        // unbekannter Opcode
        }
    }
}

// Lese-Thread (Protokollverstoß) und Schreib-Queue (disconnect) können gleichzeitig schließen.
- (void)close {
    @synchronized (self) {
        if (_closed) return;
        _closed = YES;
    }
    [self sendFrame:0x8 payload:[NSData data]];
    [_tls close];
}

- (void)dealloc { [_tls close]; }

@end
