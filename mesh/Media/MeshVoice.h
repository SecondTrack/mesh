// Sprachnachrichten aufnehmen und abspielen (wie in der Android-App):
// PCM aufnehmen → Aufbereitung bzw. Stimmeffekt → AAC. Aufnahme und Encode laufen asynchron;
// das Ergebnis kommt per Delegate. Einstellungen: MeshVoiceSettings.
#import <Foundation/Foundation.h>

@protocol MeshVoiceDelegate <NSObject>
@optional
- (void)voicePlaybackFinished;
- (void)voiceRecordingFinished:(NSData *)audio seconds:(int)seconds;  // audio nil = verworfen/zu kurz
@end

extern const NSTimeInterval MeshVoiceMaxSeconds;   // längste Sprachnachricht (klein genug für Relays)

@interface MeshVoice : NSObject
@property (nonatomic, mesh_weak) id<MeshVoiceDelegate> delegate;
@property (nonatomic, copy) NSString *effect;   // nil = MeshVoiceSettings currentEffect
@property (nonatomic, readonly) BOOL recording;
@property (nonatomic, readonly) BOOL playing;

- (BOOL)startRecording;
- (void)stopRecording;    // → voiceRecordingFinished:seconds:
- (void)cancelRecording;

- (void)play:(NSData *)aac;
- (void)stop;

// Für das Audio-Labor: unbearbeitete Aufnahme (PCM16, 16 kHz mono; der Aufrufer überschreibt
// sie mit MeshWipe, wenn er sie nicht mehr braucht) und Abspielen von PCM mit der eingestellten
// Wiedergabe-Verstärkung.
- (BOOL)startRawRecording:(NSTimeInterval)maxSeconds;
- (NSMutableData *)stopRawRecording;
- (void)playPCM:(NSData *)pcm;
@end
