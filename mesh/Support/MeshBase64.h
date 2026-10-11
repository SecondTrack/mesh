// Base64 nach RFC 4648 ohne Zeilenumbrüche.
// Eigene Implementierung: die NSData-Base64-API gibt es erst ab iOS 7.
#import <Foundation/Foundation.h>

@interface MeshBase64 : NSObject
+ (NSString *)encode:(NSData *)data;
+ (NSData *)decode:(NSString *)str;     // ignoriert Whitespace, stoppt beim ersten '='
@end
