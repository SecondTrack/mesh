#import "MeshNip04.h"
#import "MeshBase64.h"
#import "MeshKeys.h"
#import "MeshCrypto.h"
#import "MeshMemory.h"

@implementation MeshNip04

+ (NSString *)encrypt:(NSString *)text keys:(MeshKeys *)keys peerXonlyPub:(NSData *)peer32 {
    NSData *key = [keys ecdhSharedX:peer32];
    if (!key) return nil;
    NSData *iv = [MeshCrypto randomBytes:16];
    NSData *plain = [text dataUsingEncoding:NSUTF8StringEncoding];
    NSData *ct = plain ? [MeshCrypto aes256cbcEncrypt:plain key:key iv:iv] : nil;   // nicht als UTF-8 darstellbar: nichts verschicken
    MeshWipe(key);
    if (!ct || !iv) return nil;
    NSString *b64ct = [MeshBase64 encode:ct];
    NSString *b64iv = [MeshBase64 encode:iv];
    return [NSString stringWithFormat:@"%@?iv=%@", b64ct, b64iv];
}

+ (NSString *)decrypt:(NSString *)payload keys:(MeshKeys *)keys peerXonlyPub:(NSData *)peer32 {
    NSRange r = [payload rangeOfString:@"?iv="];
    if (r.location == NSNotFound) return nil;
    NSString *b64ct = [payload substringToIndex:r.location];
    NSString *b64iv = [payload substringFromIndex:r.location + r.length];

    NSData *ct = [MeshBase64 decode:b64ct];
    NSData *iv = [MeshBase64 decode:b64iv];
    NSData *key = [keys ecdhSharedX:peer32];
    NSData *plain = (ct && iv && key) ? [MeshCrypto aes256cbcDecrypt:ct key:key iv:iv] : nil;
    MeshWipe(key);
    if (!plain) return nil;
    return [[NSString alloc] initWithData:plain encoding:NSUTF8StringEncoding];
}

@end
