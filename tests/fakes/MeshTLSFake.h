// Schein-TLS für Tests: liefert vorbereitete Bytes, merkt sich Geschriebenes.
#import "MeshTLS.h"

@interface MeshTLS (Fake)
- (void)feed:(NSData *)bytes;                                       // weitere Eingabe
- (void)setResponder:(NSData *(^)(NSData *written))responder;       // Antwort auf das erste write:
- (NSData *)written;
- (BOOL)isOpen;
@end
