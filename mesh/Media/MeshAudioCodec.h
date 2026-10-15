// Umwandlung zwischen PCM16 (16 kHz mono), WAV und AAC/m4a.
#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

extern const double MeshAudioSampleRate;   // 16000
AudioStreamBasicDescription MeshPcmFormat(void);   // PCM16 mono, MeshAudioSampleRate

// Eigene M4A neu verpacken: ohne free-Polster und udta, Offsets korrigiert. nil, wenn sie nicht passt.
NSData *MeshCompactM4A(NSData *m4a);

@interface MeshAudioCodec : NSObject
+ (NSData *)wavFromPcm:(NSData *)pcm;      // für AVAudioPlayer
+ (NSData *)pcmToAac:(NSData *)pcm;        // 24 kbit/s, damit Events klein bleiben
+ (NSData *)aacToPcm:(NSData *)aac maxSeconds:(NSTimeInterval)maxSeconds;   // bricht bei maxSeconds ab
@end
