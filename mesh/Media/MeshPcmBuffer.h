// Aufnahmepuffer fester Größe für beide Rekorder: wird einmal in voller Länge angelegt, wächst
// also nicht (keine Kopien im freigegebenen Speicher), nimmt nach der Obergrenze nichts mehr an
// und ist vom Audio-Thread aus beschreibbar.
#import <Foundation/Foundation.h>

@interface MeshPcmBuffer : NSObject
- (instancetype)initWithCapacity:(NSUInteger)bytes;
- (void)append:(const void *)bytes length:(NSUInteger)length;   // threadsicher
- (NSMutableData *)take;   // genaue Kopie des Inhalts; der Puffer wird überschrieben und ist danach leer
@end
