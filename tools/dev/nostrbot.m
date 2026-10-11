// nostrbot.m — simulierter Nostr-Account auf dem Mac (Test-Gegenstelle für die iOS-App).
// Spricht dasselbe Format wie Android und iPod: MeshEnvelope über Signal, sobald das Bundle der
// Gegenseite bekannt ist, sonst NIP-44 (NIP-04 als Rückfall); das eigene Bundle reist mit.
// Hält einen festen Schlüssel (~/.mesh-bot-seckey), zeigt npub (auch als QR), beantwortet DMs als
// Antwort auf die empfangene Nachricht und verbindet sich nach Abbrüchen neu. Kommandos (Terminal
// oder Datei per tail -f) gehen an den letzten Absender:
//   text <Nachricht>   antwort <Nachricht>   bild   sprache   react <emoji>
//   timer <Sekunden> [sent]   loeschen   leeren   datei   karte   an <npub>
//
// Bauen: tools/dev/build.sh nostrbot
#import <Foundation/Foundation.h>
#import "MeshKeys.h"
#import "MeshEvent.h"
#import "MeshNip04.h"
#import "MeshNip44.h"
#import "MeshEnvelope.h"
#import "MeshSignal.h"
#import "MeshHex.h"
#import "MeshBech32.h"
#import "MeshCrypto.h"
#import "MeshPayload.h"
#import "MeshAudioCodec.h"
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>
#import "botpic.h"   // kBotPic = data-URI-Avatar

static NSString *const kRelay = @"wss://relay.primal.net";

static MeshKeys *gKeys;
static NSString *gMyHex;
static NSURLSession *gSession;
static NSURLSessionWebSocketTask *gWS;
static NSString *gPeerHex;          // letzter Absender: Ziel der Kommandos
static NSString *gLastReceived;     // cmid der zuletzt empfangenen Nachricht
static NSString *gLastSent;         // cmid der zuletzt gesendeten Nachricht
static NSMutableSet *gSeen;         // Event-IDs (mehrfach zugestellt nach Neuverbinden)
static MeshSignal *gSignal;
static NSMutableDictionary *gBundles;   // Bundle je Absender (aus \1mesh:mb:)

// Signal-Zustand des Bots in ~/.mesh-bot-signal.plist
@interface BotSignalStorage : NSObject <MeshSignalStorage>
@end
@implementation BotSignalStorage {
    NSMutableDictionary *_values;
}
- (NSString *)path { return [NSHomeDirectory() stringByAppendingPathComponent:@".mesh-bot-signal.plist"]; }
- (NSData *)signalValueForKey:(NSString *)key {
    if (!_values) _values = [[NSDictionary dictionaryWithContentsOfFile:[self path]] mutableCopy] ?: [NSMutableDictionary dictionary];
    return _values[key];
}
- (BOOL)setSignalValue:(NSData *)value forKey:(NSString *)key {
    [self signalValueForKey:key];
    if (value) _values[key] = value; else [_values removeObjectForKey:key];
    return [_values writeToFile:[self path] atomically:YES];
}
@end

static void connectRelay(void);

static void sendJSON(NSArray *arr) {
    NSData *d = [NSJSONSerialization dataWithJSONObject:arr options:0 error:NULL];
    NSString *s = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];
    [gWS sendMessage:[[NSURLSessionWebSocketMessage alloc] initWithString:s] completionHandler:^(NSError *e){
        if (e) NSLog(@"send err: %@", e);
    }];
}

static void publish(MeshEvent *e) { sendJSON(@[@"EVENT", [e toJSONObject]]); }

static NSString *shortText(NSString *s) {
    s = [s stringByReplacingOccurrencesOfString:@"\1" withString:@"␁"];
    return s.length > 70 ? [[s substringToIndex:70] stringByAppendingString:@"…"] : s;
}

// Verschlüsselt wie die App: Signal, sonst NIP-44 bis 64 KB, darüber NIP-04.
static void sendPlain(NSString *peerHex, NSString *plain, NSString *what) {
    NSData *peer = [MeshHex decode:peerHex];
    NSUInteger bytes = [plain lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    NSString *box = [gSignal encrypt:plain to:peerHex bundle:gBundles[peerHex] verified:NO refused:NULL];
    if (box) what = [what stringByAppendingString:@" (Signal)"];
    else box = bytes <= MeshNip44MaxPlaintext ? [MeshNip44 encrypt:plain keys:gKeys peerXonlyPub:peer]
                                              : [MeshNip04 encrypt:plain keys:gKeys peerXonlyPub:peer];
    if (!box) return;
    MeshEvent *e = [MeshEvent kind:4 content:box tags:@[@[@"p", peerHex]]];
    if ([e signWithKeys:gKeys]) { publish(e); NSLog(@"-> %@ an %@: %@", what, [peerHex substringToIndex:8], shortText(plain)); }
}

static void sendMessage(NSString *peerHex, NSString *content, NSString *replyTo) {
    gLastSent = [MeshEnvelope newMessageId];
    NSString *bundle = [gSignal hasSessionWith:peerHex] ? [gSignal bundle] : [gSignal bundleWithFreshOneTimeKey];
    sendPlain(peerHex, [MeshEnvelope message:content cmid:gLastSent replyTo:replyTo timer:0 mode:MeshTimerFromRead bundle:bundle], @"Nachricht");
}

static NSString *describe(MeshEnvelope *env) {
    switch (env.type) {
        case MeshEnvelopeReaction:  return [NSString stringWithFormat:@"Reaktion %@ auf %@", env.emoji.length ? env.emoji : @"(entfernt)", env.target];
        case MeshEnvelopeDelete:    return [NSString stringWithFormat:@"Für alle löschen: %@", env.target];
        case MeshEnvelopeClear:     return @"Chat für alle leeren";
        case MeshEnvelopeTimer:     return [NSString stringWithFormat:@"Timer %d s (%@)", env.timer, env.timerMode == MeshTimerFromSent ? @"ab gesendet" : @"ab gesehen"];
        case MeshEnvelopeHello:     return @"Handshake";
        case MeshEnvelopeFileChunk: return @"Dateiteil";
        case MeshEnvelopeIgnored:   return @"(ignoriert)";
        case MeshEnvelopeMessage:   break;
    }
    return [NSString stringWithFormat:@"Nachricht cmid=%@%@%@: %@", env.cmid.length ? env.cmid : @"-",
            env.replyTo.length ? [@" antwortet auf " stringByAppendingString:env.replyTo] : @"",
            env.timer ? [NSString stringWithFormat:@" timer=%d", env.timer] : @"", shortText(env.content)];
}

static void handleMessage(MeshEvent *e, MeshEnvelope *env) {
    gLastReceived = env.cmid.length ? env.cmid : e.eventId;
    MeshPayload *p = [MeshPayload parse:env.content];
    NSString *answer;
    switch (p.kind) {
        case MeshPayloadImage: answer = @"📷 Bild bekommen! ✅"; break;
        case MeshPayloadVoice: {
            NSString *path = [NSString stringWithFormat:@"/tmp/mesh-voice-%ds-%@.m4a", p.seconds, [e.eventId substringToIndex:8]];
            [p.data writeToFile:path atomically:YES];
            NSLog(@"🎤 Sprache: %d s, %lu Bytes -> %@", p.seconds, (unsigned long)p.data.length, path);
            answer = [NSString stringWithFormat:@"🎤 Sprachnachricht bekommen (%ds)! ✅", p.seconds];
            break;
        }
        case MeshPayloadFile:  answer = [NSString stringWithFormat:@"📄 Datei „%@“ bekommen (%lu Bytes) ✅", p.fileName, (unsigned long)p.data.length]; break;
        default:               answer = [NSString stringWithFormat:@"Echo vom Mesh-Tester: „%@“ ✅", env.content]; break;
    }
    sendMessage(e.pubkey, answer, env.cmid.length ? env.cmid : nil);
}

static void handle(NSString *msg) {
    id j = [NSJSONSerialization JSONObjectWithData:[msg dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
    if (![j isKindOfClass:[NSArray class]] || [j count] < 1) return;
    NSArray *a = j; NSString *type = a[0];
    if ([type isEqualToString:@"EVENT"] && a.count >= 3) {
        MeshEvent *e = [MeshEvent fromJSONObject:a[2]];
        if (e.kind != 4 || ![e verify] || [gSeen containsObject:e.eventId]) return;
        [gSeen addObject:e.eventId];
        NSData *peer = [MeshHex decode:e.pubkey];
        BOOL signal = [e.content hasPrefix:MeshSignalScheme], nip04 = [e.content rangeOfString:@"?iv="].location != NSNotFound;
        NSString *plain = signal ? [gSignal decrypt:e.content from:e.pubkey verified:NO]
                        : nip04 ? [MeshNip04 decrypt:e.content keys:gKeys peerXonlyPub:peer]
                                : [MeshNip44 decrypt:e.content keys:gKeys peerXonlyPub:peer];
        if (!plain) { if (signal) NSLog(@"<- Signal von %@: nicht entschlüsselbar", [e.pubkey substringToIndex:8]); return; }
        MeshEnvelope *env = [MeshEnvelope parse:plain];
        if (env.bundle) gBundles[e.pubkey] = env.bundle;
        NSLog(@"<- %@ von %@: %@", signal ? @"Signal" : nip04 ? @"NIP-04" : @"NIP-44", [e.pubkey substringToIndex:8], describe(env));
        gPeerHex = e.pubkey;
        if (env.type == MeshEnvelopeMessage) handleMessage(e, env);
    } else if ([type isEqualToString:@"OK"] && a.count >= 3) {
        NSLog(@"relay OK: %@ %@", a[1], a.count >= 4 ? a[3] : @"");
    }
}

// Testbild: Farbverlauf mit Kreis, 480 × 360, als JPEG.
static NSData *testJPEG(void) {
    size_t w = 480, h = 360;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, w, h, 8, 0, cs, kCGImageAlphaNoneSkipLast);
    for (size_t y = 0; y < h; y++) {
        CGContextSetRGBFillColor(ctx, 0.1, 0.3 + 0.6 * y / h, 0.6, 1);
        CGContextFillRect(ctx, CGRectMake(0, y, w, 1));
    }
    CGContextSetRGBFillColor(ctx, 0.18, 0.9, 0.66, 1);
    CGContextFillEllipseInRect(ctx, CGRectMake(w / 2 - 80, h / 2 - 80, 160, 160));
    CGImageRef img = CGBitmapContextCreateImage(ctx);
    NSMutableData *jpeg = [NSMutableData data];
    CGImageDestinationRef dst = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)jpeg, CFSTR("public.jpeg"), 1, NULL);
    CGImageDestinationAddImage(dst, img, (__bridge CFDictionaryRef)@{ (__bridge id)kCGImageDestinationLossyCompressionQuality: @0.7 });
    CGImageDestinationFinalize(dst);
    CFRelease(dst); CGImageRelease(img); CGContextRelease(ctx); CGColorSpaceRelease(cs);
    return jpeg;
}

// Testton: drei aufsteigende Töne, 3 s, als AAC wie aus der App.
static NSData *testVoice(void) {
    NSUInteger n = (NSUInteger)(3 * MeshAudioSampleRate);
    NSMutableData *pcm = [NSMutableData dataWithLength:n * 2];
    int16_t *s = pcm.mutableBytes;
    for (NSUInteger i = 0; i < n; i++) {
        double f = i < n / 3 ? 440 : i < 2 * n / 3 ? 554 : 659;
        s[i] = (int16_t)(9000 * sin(2 * M_PI * f * i / MeshAudioSampleRate));
    }
    return [MeshAudioCodec pcmToAac:pcm];
}

static void command(NSString *line) {
    line = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([line hasPrefix:@"an "]) {
        NSString *hrp = nil;
        NSData *raw = [MeshBech32 decode:[line substringFromIndex:3] hrp:&hrp];
        if (raw.length == 32 && [hrp isEqualToString:@"npub"]) { gPeerHex = [MeshHex encode:raw]; NSLog(@"Ziel: %@", gPeerHex); }
        return;
    }
    if (!gPeerHex) { NSLog(@"noch kein Ziel: erst vom iPod schreiben oder „an <npub>“"); return; }
    if ([line hasPrefix:@"text "]) sendMessage(gPeerHex, [line substringFromIndex:5], nil);
    else if ([line hasPrefix:@"antwort "]) sendMessage(gPeerHex, [line substringFromIndex:8], gLastReceived);
    else if ([line isEqualToString:@"bild"]) sendMessage(gPeerHex, [MeshPayload contentWithImage:testJPEG()], nil);
    else if ([line isEqualToString:@"sprache"]) sendMessage(gPeerHex, [MeshPayload contentWithVoice:testVoice() seconds:3], nil);
    else if ([line hasPrefix:@"react "] && gLastReceived)
        sendPlain(gPeerHex, [MeshEnvelope reactionTo:gLastReceived emoji:[line substringFromIndex:6]], @"Reaktion");
    else if ([line hasPrefix:@"timer "]) {
        NSArray *parts = [[line substringFromIndex:6] componentsSeparatedByString:@" "];
        BOOL sent = parts.count > 1 && [parts[1] isEqualToString:@"sent"];
        sendPlain(gPeerHex, [MeshEnvelope timer:[parts[0] intValue] mode:sent ? MeshTimerFromSent : MeshTimerFromRead], @"Timer");
    }
    else if ([line isEqualToString:@"loeschen"] && gLastSent) sendPlain(gPeerHex, [MeshEnvelope deletionOf:gLastSent], @"Löschen");
    else if ([line isEqualToString:@"leeren"]) sendPlain(gPeerHex, [MeshEnvelope clearChat], @"Leeren");
    else if ([line isEqualToString:@"datei"]) {
        NSString *note = [NSString stringWithFormat:@"Notiz vom Mesh-Tester\n\nGesendet %@.\nÄöü – Umlaute und Emoji 🎉 bleiben erhalten.\n", [NSDate date]];
        sendMessage(gPeerHex, [MeshPayload contentWithFile:[note dataUsingEncoding:NSUTF8StringEncoding] name:@"notiz.txt" mime:@"text/plain"], nil);
    }
    else if ([line isEqualToString:@"karte"]) {
        NSString *npub = [MeshBech32 encodeHrp:@"npub" data:gKeys.xonlyPub];
        sendMessage(gPeerHex, [MeshPayload contentWithContactName:@"Mesh Tester" code:[@"mesh:" stringByAppendingString:npub]], nil);
    }
    else NSLog(@"Kommandos: text | antwort | bild | sprache | datei | karte | react <emoji> | timer <s> [sent] | loeschen | leeren | an <npub>");
}

static void writeQR(NSString *npub, NSString *path) {
    CIFilter *f = [CIFilter filterWithName:@"CIQRCodeGenerator"];
    [f setValue:[npub dataUsingEncoding:NSUTF8StringEncoding] forKey:@"inputMessage"];
    CIImage *qr = [f.outputImage imageByApplyingTransform:CGAffineTransformMakeScale(10, 10)];
    CIContext *ctx = [CIContext contextWithOptions:nil];
    CGImageRef img = [ctx createCGImage:qr fromRect:qr.extent];
    CGImageDestinationRef dst = CGImageDestinationCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], CFSTR("public.png"), 1, NULL);
    CGImageDestinationAddImage(dst, img, NULL);
    CGImageDestinationFinalize(dst);
    CFRelease(dst); CGImageRelease(img);
}

static void receiveLoop(NSURLSessionWebSocketTask *task) {
    [task receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *m, NSError *e) {
        if (task != gWS) return;   // alte Verbindung
        if (e) {
            NSLog(@"Verbindung weg (%@), neu in 5 s", e.localizedDescription);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ connectRelay(); });
            return;
        }
        if (m.type == NSURLSessionWebSocketMessageTypeString) {
            NSString *s = m.string;
            dispatch_async(dispatch_get_main_queue(), ^{ handle(s); });
        }
        receiveLoop(task);
    }];
}

// Verbinden, Profil veröffentlichen, DMs der letzten Stunde abonnieren (Doppeltes fängt gSeen).
static void connectRelay(void) {
    [gWS cancel];
    gWS = [gSession webSocketTaskWithURL:[NSURL URLWithString:kRelay]];
    [gWS resume];
    receiveLoop(gWS);
    NSDictionary *profile = @{ @"name": @"Mesh Tester", @"about": @"Test-Gegenstelle vom Mac", @"picture": kBotPic };
    NSData *pj = [NSJSONSerialization dataWithJSONObject:profile options:0 error:NULL];
    MeshEvent *meta = [MeshEvent kind:0 content:[[NSString alloc] initWithData:pj encoding:NSUTF8StringEncoding] tags:@[]];
    if ([meta signWithKeys:gKeys]) publish(meta);
    long long since = (long long)[[NSDate date] timeIntervalSince1970] - 3600;
    sendJSON(@[@"REQ", @"botdm", @{@"kinds":@[@4], @"#p":@[gMyHex], @"since":@(since)}]);
    NSLog(@"verbunden mit %@ — warte auf DMs", kRelay);
}

int main(int argc, char **argv) {
    @autoreleasepool {
        // Schlüssel laden oder erzeugen (stabil -> npub bleibt gleich)
        NSString *keyPath = [NSHomeDirectory() stringByAppendingPathComponent:@".mesh-bot-seckey"];
        NSString *skHex = [NSString stringWithContentsOfFile:keyPath encoding:NSUTF8StringEncoding error:NULL];
        skHex = [skHex stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (skHex.length == 64) gKeys = [MeshKeys fromSeckey:[MeshHex decode:skHex]];
        if (!gKeys) { gKeys = [MeshKeys generate]; [[MeshHex encode:gKeys.seckey] writeToFile:keyPath atomically:YES encoding:NSUTF8StringEncoding error:NULL]; }
        gMyHex = [MeshHex encode:gKeys.xonlyPub];
        gSeen = [NSMutableSet set];
        gBundles = [NSMutableDictionary dictionary];
        gSignal = [[MeshSignal alloc] initWithStorage:[BotSignalStorage new] seed:gKeys.seckey];
        NSString *npub = [MeshBech32 encodeHrp:@"npub" data:gKeys.xonlyPub];

        printf("\n=== Mesh-Tester (simulierter Account) ===\n");
        printf("npub: %s\n", npub.UTF8String);
        printf("hex : %s\n\n", gMyHex.UTF8String);
        [npub writeToFile:@"/tmp/botnpub.txt" atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        NSString *qrPath = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"/tmp/mesh-bot-qr.png";
        writeQR(npub, qrPath);
        printf("QR  : %s\n\n", qrPath.UTF8String);

        gSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
        connectRelay();

        // Kommandos aus dem Terminal (oder einer Datei per tail -f) auf dem Main-Thread ausführen.
        [NSThread detachNewThreadWithBlock:^{
            char buf[4096];
            while (fgets(buf, sizeof buf, stdin)) {
                NSString *line = [NSString stringWithUTF8String:buf];
                dispatch_async(dispatch_get_main_queue(), ^{ command(line); });
            }
        }];
        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}
