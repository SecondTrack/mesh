#import "MeshVoice.h"
#import <AVFoundation/AVFoundation.h>
#import "MeshLog.h"
#import "MeshMemory.h"
#import "MeshVoiceSettings.h"
#import "MeshAudioDSP.h"
#import "MeshAudioCodec.h"
#import "MeshMediaCheck.h"
#import "MeshPcmRecorder.h"
#import "MeshVpioRecorder.h"

const NSTimeInterval MeshVoiceMaxSeconds = 30;

// Unter diesem Spitzenpegel gilt eine Voice-Processing-Aufnahme als stumm (Gerät ohne Unterstützung).
// Ein echtes Mikrofon rauscht auch im stillen Raum darüber; ausgewertet erst ab einer Sekunde, damit
// ein kurzes Antippen das Voice-Processing nicht abschaltet.
static const int kSilentPeak = 8;

@interface MeshVoice () <AVAudioPlayerDelegate>
@end

@implementation MeshVoice {
    id<MeshRecorder> _rec;          // nur während einer Aufnahme gesetzt
    BOOL             _raw;          // Rohaufnahme fürs Labor: kein Encode, kein Delegate
    NSString        *_effect;       // beim Start festgelegt, gilt bis zur Auslieferung
    AVAudioPlayer   *_player;
    NSUInteger       _playGeneration;   // jede Wiedergabe-Anfrage und jedes Stopp zählt hoch
}

- (void)activateSession:(NSString *)category {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:category error:NULL];
    [session setActive:YES error:NULL];
}

#pragma mark - Aufnahme

// Bevorzugt Voice-Processing (Pegelregelung und Rauschfilter wie beim iPhone), außer es war auf
// diesem Gerät schon einmal stumm. Mit Stimmeffekt immer roh: Apples Filter würden ihn verfälschen.
- (BOOL)startRecording {
    if (_rec.running) return NO;
    [self activateSession:AVAudioSessionCategoryPlayAndRecord];
    _raw = NO;

    _effect = self.effect.length ? [self.effect copy] : [MeshVoiceSettings currentEffect];
    BOOL processed = [MeshVoiceSettings useVPIO] && ![MeshVoiceSettings vpioBroken] && [_effect isEqualToString:MeshEffectNone];
    if (processed) {
        _rec = [MeshVpioRecorder new];
        if ([_rec start:MeshVoiceMaxSeconds]) { MeshLog(@"Sprache: Aufnahme mit Voice-Processing"); return YES; }
    }
    _rec = [MeshPcmRecorder new];
    if ([_rec start:MeshVoiceMaxSeconds]) { MeshLog(@"Sprache: Aufnahme roh"); return YES; }
    _rec = nil;
    return NO;
}

- (BOOL)recording { return !_raw && _rec.running; }

- (void)stopRecording {
    if (![self recording]) return;
    BOOL processed = [_rec isKindOfClass:[MeshVpioRecorder class]];
    [self deliver:[_rec stop] processed:processed];
    _rec = nil;
}

- (void)cancelRecording {
    if (![self recording]) return;
    MeshWipe([_rec stop]);
    _rec = nil;
}

static int peakOf(NSData *pcm) {
    const int16_t *s = pcm.bytes;
    int peak = 0;
    for (NSUInteger i = 0, n = pcm.length / 2; i < n; i++) peak = MAX(peak, abs(s[i]));
    return peak;
}

// Aufbereiten, kodieren, an den Delegate. Die eigenen Puffer mit dem Signal werden überschrieben;
// was Core Audio beim Kodieren intern anlegt, liegt außerhalb unserer Kontrolle.
- (void)deliver:(NSMutableData *)recorded processed:(BOOL)processed {
    NSString *effect = _effect ?: MeshEffectNone;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *aac = nil;
        int secs = 0;
        if (processed && recorded.length >= (NSUInteger)(2 * MeshAudioSampleRate) && peakOf(recorded) < kSilentPeak) {
            MeshLog(@"Sprache: Voice-Processing liefert Stille, ab jetzt roh");
            [MeshVoiceSettings setVpioBroken:YES];
        } else if (recorded.length >= (NSUInteger)MeshAudioSampleRate) {   // mindestens 0,5 s
            NSData *voice = recorded;
            if ([effect isEqualToString:MeshEffectNone]) {
                // Normale Stimme aufbereiten. Nach Voice-Processing ist schon entrauscht.
                voice = [MeshAudioDSP process:recorded noise:processed ? 0.0f : [MeshVoiceSettings labNoise]
                                           hp:[MeshVoiceSettings labHp] lp:[MeshVoiceSettings labLp]
                                     presence:[MeshVoiceSettings labPresence] gain:[MeshVoiceSettings labGain]];
            }
            // Effekte ohne vorherige Aufbereitung, so klingen sie wie in der Android-App.
            NSData *fx = [MeshAudioDSP applyEffect:voice effect:effect];   // nil: nie ohne den gewählten Effekt senden
            if (fx) {
                secs = (int)MAX(1, (fx.length / 2) / (NSInteger)MeshAudioSampleRate);
                aac = [MeshAudioCodec pcmToAac:fx];
            }
            if (fx != voice) MeshWipe(fx);
            if (voice != recorded) MeshWipe(voice);
        }
        MeshWipe(recorded);
        MeshLog(@"Sprache: fertig, Effekt %@, %d s, %lu Byte", effect, secs, (unsigned long)aac.length);
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.delegate respondsToSelector:@selector(voiceRecordingFinished:seconds:)])
                [self.delegate voiceRecordingFinished:(aac.length ? aac : nil) seconds:secs];
        });
    });
}

#pragma mark - Labor

- (BOOL)startRawRecording:(NSTimeInterval)maxSeconds {
    if (_rec.running) return NO;
    [self activateSession:AVAudioSessionCategoryPlayAndRecord];
    _rec = [MeshPcmRecorder new];
    _raw = [_rec start:maxSeconds];
    if (!_raw) _rec = nil;
    return _raw;
}

- (NSMutableData *)stopRawRecording {
    if (!_raw) return nil;
    NSMutableData *pcm = [_rec stop];
    _rec = nil;
    _raw = NO;
    return pcm;
}

#pragma mark - Wiedergabe

- (void)play:(NSData *)audio {
    [self stop];
    if (![MeshMediaCheck isAcceptableAudio:audio]) { [self playbackFailed]; return; }   // nur M4A/ADTS an den System-Decoder
    // Im Hintergrund zu PCM dekodieren, damit die Verstärkung greift; scheitert das,
    // das AAC direkt abspielen.
    NSUInteger generation = ++_playGeneration;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *pcm = [MeshAudioCodec aacToPcm:audio maxSeconds:2 * MeshVoiceMaxSeconds];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self->_playGeneration) return;   // inzwischen gestoppt oder etwas anderes gestartet
            if (pcm.length) [self playPCM:pcm];
            else            [self playData:audio];
        });
    });
}

- (void)playPCM:(NSData *)pcm {
    [self stop];
    if (!pcm.length) return;
    int level = [MeshVoiceSettings playGainLevel];
    if (level > 0) pcm = [MeshAudioDSP applyGain:pcm factor:[MeshVoiceSettings gainFactor:level]];
    [self playData:[MeshAudioCodec wavFromPcm:pcm]];
}

// WAV oder AAC über AVAudioPlayer.
- (void)playData:(NSData *)data {
    [self activateSession:AVAudioSessionCategoryPlayback];
    NSError *err = nil;
    _player = [[AVAudioPlayer alloc] initWithData:data error:&err];
    if (!_player) { MeshLog(@"Sprache: Abspielen nicht möglich: %@", err); [self playbackFailed]; return; }
    _player.delegate = self;
    _player.volume = 1.0f;
    [_player play];
}

// Auch ein Fehlschlag beendet die Wiedergabe aus Sicht des Delegates (sonst bliebe "spielt" stehen).
// Asynchron, damit der Aufrufer von play: seinen Zustand vorher fertig setzen kann.
- (void)playbackFailed {
    NSUInteger generation = _playGeneration;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (generation != self->_playGeneration) return;
        if ([self.delegate respondsToSelector:@selector(voicePlaybackFinished)]) [self.delegate voicePlaybackFinished];
    });
}

- (BOOL)playing { return _player != nil && _player.playing; }

- (void)stop {
    _playGeneration++;
    [_player stop];
    _player = nil;
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)p successfully:(BOOL)flag {
    _player = nil;
    if ([self.delegate respondsToSelector:@selector(voicePlaybackFinished)]) [self.delegate voicePlaybackFinished];
}

- (void)dealloc {
    MeshWipe([_rec stop]);
    _player.delegate = nil;
    [_player stop];
}

@end
