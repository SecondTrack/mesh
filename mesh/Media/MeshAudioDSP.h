// Signalverarbeitung auf PCM16 (16 kHz mono): Aufbereitung, Verstärkung, Stimmeffekte.
#import <Foundation/Foundation.h>

// Stimmeffekte (gleiche Kennungen wie in der Android-App, so auch gespeichert).
extern NSString *const MeshEffectNone;
extern NSString *const MeshEffectHigh;
extern NSString *const MeshEffectDeep;
extern NSString *const MeshEffectRobot;
extern NSString *const MeshEffectAlien;
extern NSString *const MeshEffectAnonym;
extern NSString *const MeshEffectChipmunk;
extern NSString *const MeshEffectChipmunkAnon;

@interface MeshAudioDSP : NSObject
// Aufbereitung wie im Audio-Labor: Hochpass, Tiefpass, Rauschfilter (noise 0…4),
// Präsenz-Anhebung um 3 kHz, Normalisierung auf -3 dBFS, Endverstärkung mit Soft-Limiter.
+ (NSData *)process:(NSData *)pcm noise:(float)noise hp:(float)hpHz lp:(float)lpHz presence:(float)presenceDb gain:(float)gain;
+ (NSData *)applyGain:(NSData *)pcm factor:(double)factor;
+ (NSData *)applyEffect:(NSData *)pcm effect:(NSString *)effect;   // nil, wenn der Effekt scheitert; siehe MeshVoiceSettings allEffects
@end
