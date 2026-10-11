// Mikrofon direkt in den Arbeitsspeicher (PCM16, 16 kHz mono), damit die Stimme nie
// unverschlüsselt im Dateisystem liegt. Umgesetzt von MeshVpioRecorder (Voice-Processing,
// Apples Pegelregelung und Rauschfilter) und MeshPcmRecorder (AudioQueue, rohes Signal).
#import <Foundation/Foundation.h>

@protocol MeshRecorder <NSObject>
@property (nonatomic, readonly) BOOL running;
- (BOOL)start:(NSTimeInterval)maxSeconds;   // nach maxSeconds wird nichts mehr angehängt
- (NSMutableData *)stop;                    // Aufnahme, vom Aufrufer mit MeshWipe zu löschen; nil ohne Start
@end
