// Kleiner, strikter JSON-Parser/-Serialisierer (RFC 8259) für iOS 4,
// wo NSJSONSerialization fehlt. Wird nur über MeshJSON benutzt.
//
// Abbildung wie NSJSONSerialization: Objekt → NSDictionary, Array → NSArray,
// String → NSString, Zahl → NSNumber, true/false → NSNumber (BOOL), null → NSNull.
// Schutz gegen bösartige Eingaben: maximale Verschachtelungstiefe und Eingabegröße.
#import <Foundation/Foundation.h>

enum {
    MeshJSONMaxDepth = 64,
    MeshJSONMaxBytes = 4 * 1024 * 1024
};

@interface MeshJSONCodec : NSObject
+ (id)objectWithData:(NSData *)data;       // nil bei ungültigem oder zu großem Dokument
+ (NSData *)dataWithObject:(id)object;     // nil bei nicht darstellbaren Werten
@end
