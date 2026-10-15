// JSON lesen und schreiben: NSJSONSerialization ab iOS 5, sonst eigener Parser (MeshJSONCodec).
#import <Foundation/Foundation.h>

@interface MeshJSON : NSObject
+ (id)objectWithData:(NSData *)data;            // nil bei ungültigem JSON
+ (NSData *)dataWithObject:(id)object;          // nil, wenn nicht serialisierbar
@end

// Vor dem Parsen: Schachtelung von [ und { höchstens maxDepth (außerhalb von Strings gezählt). Schützt
// Parser mit Rekursion vor tief verschachteltem JSON von außen.
BOOL MeshJSONShallow(NSData *data, NSUInteger maxDepth);
