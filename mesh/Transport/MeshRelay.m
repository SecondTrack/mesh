#import "MeshRelay.h"
#import "MeshWebSocket.h"
#import "MeshEvent.h"
#import "MeshLog.h"
#import "MeshJSON.h"
#import <libkern/OSAtomic.h>

// Threads: connect/disconnect/send und alle Delegate-Callbacks laufen auf dem Main-Thread,
// das Lesen auf einem eigenen Thread, Schreiben und Schließen seriell auf _writeQueue.
// _connected und _thread werden nur auf dem Main-Thread verändert.
@implementation MeshRelay {
    MeshWebSocket *_ws;
    NSString *_host, *_path;
    int _port;
    NSThread *_thread;
    dispatch_queue_t _writeQueue;   // serielles Senden abseits des Main-Threads (sonst UI-Hänger)
    BOOL _connected;
    volatile BOOL _stop;            // vom Main-Thread gesetzt, vom Lese-Thread gelesen
    volatile int64_t _queued;       // Bytes in _writeQueue (atomar: Main-Thread zählt hoch, Schreib-Queue runter)
    volatile int32_t _refused;      // seit dem letzten Leerlauf ein großes Event abgelehnt
}

- (long long)queuedBytes { return OSAtomicAdd64Barrier(0, &_queued); }

- (instancetype)initWithURL:(NSString *)wssUrl {
    if ((self = [super init])) {
        _url = [wssUrl copy];
        _writeQueue = dispatch_queue_create("mesh.relay.write", DISPATCH_QUEUE_SERIAL);
        [self parseURL:wssUrl];
    }
    return self;
}

- (void)dealloc { mesh_dispatch_release(_writeQueue); }

// wss://host[:port][/path]. Die Relays stehen fest im Code (MeshSession); es gibt nur TLS.
- (void)parseURL:(NSString *)u {
    NSString *rest = [u hasPrefix:@"wss://"] ? [u substringFromIndex:6] : u;
    _port = 443;
    NSRange slash = [rest rangeOfString:@"/"];
    NSString *hostport = slash.location == NSNotFound ? rest : [rest substringToIndex:slash.location];
    _path = slash.location == NSNotFound ? @"/" : [rest substringFromIndex:slash.location];
    NSRange colon = [hostport rangeOfString:@":"];
    if (colon.location != NSNotFound) {
        _host = [hostport substringToIndex:colon.location];
        int port = [[hostport substringFromIndex:colon.location + 1] intValue];
        if (port > 0 && port < 65536) _port = port;
    } else {
        _host = hostport;
    }
}

- (BOOL)connected { return _connected; }

- (BOOL)connecting { return _thread != nil && !_connected; }

- (void)connect {
    if (_thread) return;
    _stop = NO;
    _ws = [[MeshWebSocket alloc] init];
    _ws.socksCredential = _socksCredential;
    _thread = [[NSThread alloc] initWithTarget:self selector:@selector(run:) object:_ws];
    [_thread start];
}

- (void)disconnect {
    _stop = YES;
    MeshWebSocket *ws = _ws;
    dispatch_async(_writeQueue, ^{ [ws close]; });
}

- (void)run:(MeshWebSocket *)ws {
    @autoreleasepool {
        MeshLog(@"Relay connecting: %@ (%@:%d%@)", _url, _host, _port, _path);
        NSString *err = nil;
        BOOL up = [ws connectHost:_host port:_port path:_path error:&err] && !_stop;
        if (up) {
            MeshLog(@"Relay CONNECTED: %@", _url);
            [self onMain:^{ self->_connected = YES; }];
            [self tell:@selector(relayDidConnect:) call:^(id<MeshRelayDelegate> d) { [d relayDidConnect:self]; }];
            while (!_stop) {
                NSString *text = [ws readText];
                MeshLog(@"WS<< %@: %lu Zeichen", _url, (unsigned long)text.length);   // nie Inhalte loggen
                if (!text) break;
                [self handleMessage:text];
            }
        } else {
            MeshLog(@"Relay FAILED %@: %@", _url, err);
        }
        [ws close];   // auch nach EOF oder Netzfehler: sonst bliebe der Socket offen
        NSString *reason = _stop ? nil : (up ? @"connection closed" : (err ?: @"connect failed"));
        [self onMain:^{ self->_connected = NO; self->_thread = nil; }];
        [self tell:@selector(relay:didDisconnectWithError:) call:^(id<MeshRelayDelegate> d) { [d relay:self didDisconnectWithError:reason]; }];
    }
}

// Relay-Nachrichten nach NIP-01/NIP-42. Alles mit falschen Typen wird verworfen.
- (void)handleMessage:(NSString *)text {
    NSArray *arr = [MeshJSON objectWithData:[text dataUsingEncoding:NSUTF8StringEncoding]];
    if (![arr isKindOfClass:[NSArray class]] || arr.count < 2 || ![arr[0] isKindOfClass:[NSString class]]) return;
    NSString *type = arr[0];
    id a1 = arr[1];
    BOOL a1String = [a1 isKindOfClass:[NSString class]];

    if ([type isEqualToString:@"EVENT"] && arr.count >= 3 && a1String) {
        MeshEvent *e = [MeshEvent fromJSONObject:arr[2]];
        if (e.eventId && [self.verified containsId:e.eventId]) return;   // schon von einem anderen Relay geliefert
        BOOL ok = e && [e verify];
        MeshLog(@"EVENT kind=%ld verify=%d", (long)e.kind, ok);
        if (ok) [self.verified addId:e.eventId];
        if (ok) [self tell:@selector(relay:didReceiveEvent:subId:) call:^(id<MeshRelayDelegate> d) { [d relay:self didReceiveEvent:e subId:a1]; }];
    } else if ([type isEqualToString:@"EOSE"] && a1String) {
        [self tell:@selector(relay:didFinishStoredEvents:) call:^(id<MeshRelayDelegate> d) { [d relay:self didFinishStoredEvents:a1]; }];
    } else if ([type isEqualToString:@"AUTH"] && a1String && [a1 length] <= 1024) {
        MeshLog(@"AUTH-Challenge von %@", _url);
        [self tell:@selector(relay:didRequestAuth:) call:^(id<MeshRelayDelegate> d) { [d relay:self didRequestAuth:a1]; }];
    } else if ([type isEqualToString:@"OK"] && arr.count >= 3 && a1String && [arr[2] isKindOfClass:[NSNumber class]]) {
        BOOL accepted = [arr[2] boolValue];
        NSString *msg = (arr.count >= 4 && [arr[3] isKindOfClass:[NSString class]]) ? arr[3] : @"";
        [self tell:@selector(relay:didGetOKForEvent:accepted:message:) call:^(id<MeshRelayDelegate> d) {
            [d relay:self didGetOKForEvent:a1 accepted:accepted message:msg];
        }];
    }
    // NOTICE/CLOSED: bewusst ignoriert.
}

#pragma mark - Senden

- (BOOL)sendJSON:(NSArray *)arr {
    if (!_connected) return NO;
    NSData *d = [MeshJSON dataWithObject:arr];
    NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    int64_t bytes = (int64_t)d.length;
    d = nil;
    OSAtomicAdd64Barrier(bytes, &_queued);
    // Senden auf serieller Hintergrund-Queue: blockiert nie den Main-Thread (TLS-Write wartet
    // ggf. kurz auf den I/O-Lock des Lese-Threads). Reihenfolge bleibt erhalten.
    MeshWebSocket *ws = _ws;
    dispatch_async(_writeQueue, ^{
        @autoreleasepool { [ws sendText:s]; }   // nach close liefert sendText nur NO
        if (OSAtomicAdd64Barrier(-bytes, &self->_queued) == 0 && OSAtomicCompareAndSwap32Barrier(1, 0, &self->_refused))
            [self tell:@selector(relayDidDrain:) call:^(id<MeshRelayDelegate> dl) { [dl relayDidDrain:self]; }];
    });
    return YES;
}

- (void)subscribe:(NSString *)subId filter:(NSDictionary *)filter {
    [self sendJSON:@[@"REQ", subId, filter ?: @{}]];
}

- (void)unsubscribe:(NSString *)subId {
    [self sendJSON:@[@"CLOSE", subId]];
}

- (void)notifyWhenDrained {
    OSAtomicCompareAndSwap32Barrier(0, 1, &_refused);
    if (self.queuedBytes == 0 && OSAtomicCompareAndSwap32Barrier(1, 0, &_refused))
        [self tell:@selector(relayDidDrain:) call:^(id<MeshRelayDelegate> d) { [d relayDidDrain:self]; }];
}

// Große Events (Gruppen-Medien) nicht stapeln: jedes Relay hält seine eigene serialisierte Kopie, bis sie
// geschrieben ist. Geschätzt vor dem Serialisieren, damit Abgelehntes keinen Speicher kostet.
- (BOOL)publish:(MeshEvent *)event {
    if (!_connected) return NO;
    int64_t estimate = (int64_t)event.content.length + 1024;
    int64_t queued = self.queuedBytes;
    if (estimate > MeshRelayLargeEvent && queued > 0 && queued + estimate > MeshRelayQueueCap) {
        [self notifyWhenDrained];   // falls inzwischen leer geworden: gleich
        return NO;
    }
    return [self sendJSON:@[@"EVENT", [event toJSONObject]]];
}

- (void)sendAuth:(MeshEvent *)authEvent {
    [self sendJSON:@[@"AUTH", [authEvent toJSONObject]]];
}

// Delegate-Methoden sind optional und laufen immer auf dem Main-Thread.
- (void)tell:(SEL)selector call:(void (^)(id<MeshRelayDelegate> delegate))call {
    [self onMain:^{
        id<MeshRelayDelegate> d = self.delegate;
        if ([d respondsToSelector:selector]) call(d);
    }];
}

- (void)onMain:(void(^)(void))block {
    dispatch_async(dispatch_get_main_queue(), block);
}

@end
