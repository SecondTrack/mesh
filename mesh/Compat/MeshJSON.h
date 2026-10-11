// JSON lesen und schreiben: NSJSONSerialization ab iOS 5, sonst eigener Parser (MeshJSONCodec).
#import <Foundation/Foundation.h>

@interface MeshJSON : NSObject
+ (id)objectWithData:(NSData *)data;            // nil bei ungültigem JSON
+ (NSData *)dataWithObject:(id)object;          // nil, wenn nicht serialisierbar
@end
