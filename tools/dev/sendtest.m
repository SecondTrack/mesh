// sendtest.m — schickt EINE NIP-04-DM vom Bot-Account an einen Ziel-Pubkey (Empfangstest).
// Aufruf: sendtest <ziel-hex> "<text>"
#import <Foundation/Foundation.h>
#import "MeshKeys.h"
#import "MeshEvent.h"
#import "MeshNip04.h"
#import "MeshHex.h"

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 3) { printf("usage: sendtest <hex> <text>\n"); return 1; }
        NSString *targetHex = [NSString stringWithUTF8String:argv[1]];
        NSString *text = [NSString stringWithUTF8String:argv[2]];

        NSString *keyPath = [NSHomeDirectory() stringByAppendingPathComponent:@".mesh-bot-seckey"];
        NSString *skHex = [[NSString stringWithContentsOfFile:keyPath encoding:NSUTF8StringEncoding error:NULL]
                           stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        MeshKeys *keys = [MeshKeys fromSeckey:[MeshHex decode:skHex]];
        NSString *box = [MeshNip04 encrypt:text keys:keys peerXonlyPub:[MeshHex decode:targetHex]];
        MeshEvent *e = [MeshEvent kind:4 content:box tags:@[@[@"p", targetHex]]];
        [e signWithKeys:keys];

        NSData *d = [NSJSONSerialization dataWithJSONObject:@[@"EVENT", [e toJSONObject]] options:0 error:NULL];
        NSString *msg = [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding];

        // Zu allen speichernden Relays publizieren, damit die DM garantiert liegenbleibt.
        NSArray *relays = @[ @"wss://nos.lol", @"wss://relay.primal.net", @"wss://nostr.mom", @"wss://relay.snort.social" ];
        NSURLSession *s = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
        for (NSString *url in relays) {
            NSURLSessionWebSocketTask *ws = [s webSocketTaskWithURL:[NSURL URLWithString:url]];
            [ws resume];
            __block void (^rcv)(void) = ^{};
            rcv = ^{ [ws receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *m, NSError *err){
                if (m.string) printf("%s: %s\n", url.UTF8String, m.string.UTF8String);
                if (!err) rcv();
            }]; };
            rcv();
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [ws sendMessage:[[NSURLSessionWebSocketMessage alloc] initWithString:msg] completionHandler:^(NSError *err){
                    if (!err) printf("→ gesendet an %s über %s\n", [targetHex substringToIndex:8].UTF8String, url.UTF8String);
                }];
            });
        }
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:6];
        while ([until timeIntervalSinceNow] > 0) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
    }
    return 0;
}
