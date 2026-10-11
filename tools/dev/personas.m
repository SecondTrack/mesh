// personas.m — fünf Test-Accounts mit Profilnamen schreiben dem iPod (Design-Check der Chatliste
// und Blasen: lange und kurze Texte, Emojis, Umbrüche). Schlüssel bleiben in ~/.mesh-personas/,
// damit wiederholte Läufe in dieselben Chats schreiben. NIP-44 im Umschlag der Apps.
// Profilbilder aus tools/dev/persona-avatars/: <id>.jpg (zufällige Fotos von picsum.photos, Unsplash-
// Lizenz) randlos zugeschnitten, sonst <id>.png (Noto-Emoji, Apache 2.0) auf Farbfläche; als
// JPEG-data:-URI (die App lädt keine Bilder aus dem Netz).
// Aufruf: personas [ziel-hex] [profil]   (ohne Ziel: wer dem Bot zuletzt geschrieben hat;
//                                         "profil": nur Profile neu veröffentlichen, keine Nachrichten)
#import <Foundation/Foundation.h>
#import "MeshKeys.h"
#import "MeshEvent.h"
#import "MeshNip44.h"
#import "MeshEnvelope.h"
#import "MeshHex.h"
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>

static NSArray *relays(void) { return @[@"wss://nos.lol", @"wss://relay.primal.net", @"wss://nostr.mom", @"wss://relay.snort.social"]; }

static void spin(double seconds) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while ([until timeIntervalSinceNow] > 0) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
}

static NSString *json(id obj) {
    return [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:obj options:0 error:NULL] encoding:NSUTF8StringEncoding];
}

static MeshKeys *keysFor(NSString *name) {
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@".mesh-personas"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *path = [dir stringByAppendingPathComponent:name];
    NSString *hex = [[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL]
                     stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (hex.length == 64) return [MeshKeys fromSeckey:[MeshHex decode:hex]];
    MeshKeys *k = [MeshKeys generate];
    [[MeshHex encode:k.seckey] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0600} ofItemAtPath:path error:NULL];
    return k;
}

// Wer hat dem Bot zuletzt geschrieben? (DMs mit p = Bot)
static NSString *lastPeerOfBot(void) {
    NSString *sk = [[NSString stringWithContentsOfFile:[NSHomeDirectory() stringByAppendingPathComponent:@".mesh-bot-seckey"]
                                              encoding:NSUTF8StringEncoding error:NULL]
                    stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (sk.length != 64) return nil;
    NSString *bot = [MeshHex encode:[MeshKeys fromSeckey:[MeshHex decode:sk]].xonlyPub];
    __block NSString *best = nil; __block long long bestAt = 0;
    NSURLSession *s = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    NSURLSessionWebSocketTask *ws = [s webSocketTaskWithURL:[NSURL URLWithString:@"wss://relay.primal.net"]];
    [ws resume];
    __block void (^rcv)(void);
    rcv = ^{ [ws receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *m, NSError *err) {
        NSArray *a = m.string ? [NSJSONSerialization JSONObjectWithData:[m.string dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL] : nil;
        if ([a isKindOfClass:[NSArray class]] && a.count >= 3 && [a[0] isEqual:@"EVENT"]) {
            NSDictionary *e = a[2];
            long long at = [e[@"created_at"] longLongValue];
            if (at > bestAt && ![e[@"pubkey"] isEqual:bot]) { bestAt = at; best = e[@"pubkey"]; }
        }
        if (!err) rcv();
    }]; };
    rcv();
    [ws sendMessage:[[NSURLSessionWebSocketMessage alloc] initWithString:json(@[@"REQ", @"p", @{@"kinds": @[@4], @"#p": @[bot], @"limit": @30}])]
  completionHandler:^(NSError *e) {}];
    spin(4);
    [ws cancel];
    return best;
}

// 256 × 256: Farbfläche, Emoji mittig auf 70 %.
static NSString *avatarURI(NSString *pngPath, uint32_t rgb) {
    CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:pngPath], NULL);
    CGImageRef emoji = src ? CGImageSourceCreateImageAtIndex(src, 0, NULL) : NULL;
    if (src) CFRelease(src);
    if (!emoji) return nil;
    const size_t side = 256;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(NULL, side, side, 8, 0, cs, kCGImageAlphaPremultipliedLast);
    CGContextSetRGBFillColor(ctx, ((rgb >> 16) & 0xFF) / 255.0, ((rgb >> 8) & 0xFF) / 255.0, (rgb & 0xFF) / 255.0, 1);
    CGContextFillRect(ctx, CGRectMake(0, 0, side, side));
    if ([pngPath hasSuffix:@".jpg"]) {   // Foto: Mitte quadratisch, randlos
        CGFloat w = CGImageGetWidth(emoji), h = CGImageGetHeight(emoji), s = side / MIN(w, h);
        CGContextDrawImage(ctx, CGRectMake((side - w * s) / 2, (side - h * s) / 2, w * s, h * s), emoji);
    } else {
        CGFloat e = side * 0.7;
        CGContextDrawImage(ctx, CGRectMake((side - e) / 2, (side - e) / 2, e, e), emoji);
    }
    CGImageRef out = CGBitmapContextCreateImage(ctx);
    NSMutableData *jpeg = [NSMutableData data];
    CGImageDestinationRef dst = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)jpeg, CFSTR("public.jpeg"), 1, NULL);
    CGImageDestinationAddImage(dst, out, (__bridge CFDictionaryRef)@{(__bridge id)kCGImageDestinationLossyCompressionQuality: @0.85});
    CGImageDestinationFinalize(dst);
    CFRelease(dst); CGImageRelease(out); CGImageRelease(emoji); CGContextRelease(ctx); CGColorSpaceRelease(cs);
    return [@"data:image/jpeg;base64," stringByAppendingString:[jpeg base64EncodedStringWithOptions:0]];
}

int main(int argc, char **argv) {
    @autoreleasepool {
        BOOL profileOnly = argc > 2 && !strcmp(argv[2], "profil");
        NSString *target = argc > 1 && strlen(argv[1]) == 64 ? [NSString stringWithUTF8String:argv[1]] : lastPeerOfBot();
        if (target.length != 64) { printf("kein Ziel gefunden: personas <ziel-hex>\n"); return 1; }
        printf("Ziel: %s\n", target.UTF8String);

        NSArray *personas = @[
            @{@"id": @"kalle", @"color": @0x2F6B4F, @"name": @"Onkel Kalle 🦆", @"about": @"Ententeich-Logistik seit 1987",
              @"msgs": @[@"Die Ente fliegt um Mitternacht.",
                         @"Wiederhole: Die Ente. Fliegt. Um Mitternacht. 🦆",
                         @"Bring Brot mit. Kein Vollkorn, die Ente hat Ansprüche."]},
            @{@"id": @"pfefferminz", @"color": @0x1C8F6B, @"name": @"Agentin Pfefferminz", @"about": @"Frisch. Diskret. Meistens.",
              @"msgs": @[@"Der Kühlschrank summt in Moll. Das ist das Zeichen.",
                         @"Paket 7 liegt unter dem dritten Gartenzwerg von links. Nicht den mit der Angel, der ist ein Spitzel.",
                         @"Falls jemand fragt: Wir reden über Kuchenrezepte. 🍰"]},
            @{@"id": @"zahnrad", @"color": @0x3B4A8C, @"name": @"Prof. Dr. Zahnrad", @"about": @"Lehrstuhl für angewandte Verschwörung",
              @"msgs": @[@"Hypothese: Der Toaster weiß mehr, als er zugibt.",
                         @"Koordinaten folgen:\n51° Nord\nGurkenglas\nMittwoch, kurz nach dem Tatort",
                         @"Bitte nach dem Lesen vernichten. Oder wenigstens ignorieren.",
                         @"🧀"]},
            @{@"id": @"mamabaer", @"color": @0x8C5A3B, @"name": @"Mama Bär", @"about": @"Hat immer Pflaster dabei",
              @"msgs": @[@"Der Adler ist gelandet. Also Papa. Mit Pizza. 🍕",
                         @"Hast du deine Jacke? Codewort: Zwiebel.",
                         @"Ruf zurück, wenn der Mond grün ist. Oder einfach so ❤️"]},
            @{@"id": @"gonzo", @"color": @0x5B2E8C, @"name": @"Glitch Gonzo", @"about": @"404 – Persönlichkeit nicht gefunden",
              @"msgs": @[@"pssst … das Huhn kennt die WLAN-Passwörter",
                         @"Operation Käsetoast läuft. Status: knusprig. Wiederhole: KNUSPRIG.",
                         @"Wenn der Wasserkocher pfeift, nimm die linke Treppe, zähl bis 17, sag „Banane“ zum Hausmeister und frag nach dem blauen Ordner. Der rote ist eine Falle. Der grüne ist nur Steuerkram. 🫖",
                         @"🤫🐔📶"]},
        ];

        NSURLSession *s = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
        NSMutableArray *sockets = [NSMutableArray array];
        for (NSString *url in relays()) {
            NSURLSessionWebSocketTask *ws = [s webSocketTaskWithURL:[NSURL URLWithString:url]];
            [ws resume];
            __block void (^rcv)(void);
            rcv = ^{ [ws receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *m, NSError *err) {
                if ([m.string hasPrefix:@"[\"OK\""] && [m.string rangeOfString:@"false"].location != NSNotFound) printf("%s: %s\n", url.UTF8String, m.string.UTF8String);
                if (!err) rcv();
            }]; };
            rcv();
            [sockets addObject:ws];
        }
        spin(1.5);
        void (^publish)(MeshEvent *) = ^(MeshEvent *e) {
            NSString *msg = json(@[@"EVENT", [e toJSONObject]]);
            for (NSURLSessionWebSocketTask *ws in sockets)
                [ws sendMessage:[[NSURLSessionWebSocketMessage alloc] initWithString:msg] completionHandler:^(NSError *err) {}];
        };

        NSData *peer = [MeshHex decode:target];
        for (NSDictionary *p in personas) {
            MeshKeys *k = keysFor(p[@"id"]);
            NSMutableDictionary *profile = [@{@"name": p[@"name"], @"about": p[@"about"]} mutableCopy];
            NSString *dir = [[[NSString stringWithUTF8String:__FILE__] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"persona-avatars"];
            NSString *photo = [dir stringByAppendingPathComponent:[p[@"id"] stringByAppendingPathExtension:@"jpg"]];
            if (![[NSFileManager defaultManager] fileExistsAtPath:photo]) photo = [dir stringByAppendingPathComponent:[p[@"id"] stringByAppendingPathExtension:@"png"]];
            NSString *pic = avatarURI(photo, [p[@"color"] unsignedIntValue]);
            if (pic) profile[@"picture"] = pic;
            MeshEvent *meta = [MeshEvent kind:0 content:json(profile) tags:@[]];
            [meta signWithKeys:k];
            publish(meta);
            printf("%s: Profil%s (%lu Zeichen Bild)\n", [p[@"name"] UTF8String], pic ? " mit Bild" : "", (unsigned long)pic.length);
            if (profileOnly) continue;
            for (NSString *text in p[@"msgs"]) {
                NSString *plain = [MeshEnvelope message:text cmid:[MeshEnvelope newMessageId] replyTo:nil timer:0 mode:MeshTimerFromRead bundle:nil];
                MeshEvent *e = [MeshEvent kind:4 content:[MeshNip44 encrypt:plain keys:k peerXonlyPub:peer] tags:@[@[@"p", target]]];
                [e signWithKeys:k];
                publish(e);
                spin(1.1);   // eigene Zeitstempel, Reihenfolge bleibt
            }
            printf("%s: %lu Nachrichten\n", [p[@"name"] UTF8String], (unsigned long)[p[@"msgs"] count]);
        }
        spin(3);
    }
    return 0;
}
