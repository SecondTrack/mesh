// query.m — fragt das Relay ab: eigenes kind-0 + DMs an den Bot. Zeigt was der iPod sehen sollte.
#import <Foundation/Foundation.h>
#import "MeshKeys.h"
#import "MeshHex.h"
#import "MeshBech32.h"

int main(int argc, char **argv) {
    @autoreleasepool {
        NSString *keyPath = [NSHomeDirectory() stringByAppendingPathComponent:@".mesh-bot-seckey"];
        NSString *skHex = [[NSString stringWithContentsOfFile:keyPath encoding:NSUTF8StringEncoding error:NULL]
                           stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        MeshKeys *keys = [MeshKeys fromSeckey:[MeshHex decode:skHex]];
        NSString *myHex = [MeshHex encode:keys.xonlyPub];
        printf("Bot-hex: %s\n", myHex.UTF8String);

        NSURLSession *s = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
        NSURLSessionWebSocketTask *ws = [s webSocketTaskWithURL:[NSURL URLWithString:@"wss://nos.lol"]];
        [ws resume];
        __block void (^rcv)(void) = ^{};
        rcv = ^{ [ws receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *m, NSError *err){
            if (m.string) printf("<< %s\n", m.string.UTF8String);
            if (!err) rcv();
        }]; };
        rcv();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSArray *req = @[@"REQ", @"q", @{@"kinds":@[@0], @"authors":@[myHex]}];
            NSData *d = [NSJSONSerialization dataWithJSONObject:req options:0 error:NULL];
            [ws sendMessage:[[NSURLSessionWebSocketMessage alloc] initWithString:[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding]] completionHandler:^(NSError *e){ printf(e?"REQ err\n":">> REQ kind-0 authors=self gesendet\n"); }];
        });
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:6];
        while ([until timeIntervalSinceNow] > 0) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
    }
    return 0;
}
