#import "MeshVpioRecorder.h"
#import <AudioToolbox/AudioToolbox.h>
#import "MeshAudioCodec.h"
#import "MeshLog.h"
#import "MeshMemory.h"
#import "MeshPcmBuffer.h"

static const UInt32 kMaxFrames = 4096;   // mehr liefert die AudioUnit pro Rückruf nicht

@implementation MeshVpioRecorder {
    AudioUnit _unit;
    MeshPcmBuffer *_pcm;
    int16_t *_scratch;        // vorab angelegt: im Echtzeit-Rückruf kein malloc
}

static OSStatus inputCallback(void *ref, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *ts,
                              UInt32 bus, UInt32 frames, AudioBufferList *unused) {
    MeshVpioRecorder *self = (__bridge MeshVpioRecorder *)ref;
    if (frames > kMaxFrames) return noErr;
    AudioBufferList abl;
    abl.mNumberBuffers = 1;
    abl.mBuffers[0].mNumberChannels = 1;
    abl.mBuffers[0].mDataByteSize = frames * 2;
    abl.mBuffers[0].mData = self->_scratch;
    OSStatus st = AudioUnitRender(self->_unit, flags, ts, bus, frames, &abl);
    if (st != noErr) return st;
    [self->_pcm append:self->_scratch length:(NSUInteger)frames * 2];
    return noErr;
}

// Die Voice-Processing-Unit liefert nur Eingang, solange auch ein Ausgang läuft: Stille.
static OSStatus silentOutput(void *ref, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *ts,
                             UInt32 bus, UInt32 frames, AudioBufferList *io) {
    for (UInt32 i = 0; i < io->mNumberBuffers; i++) memset(io->mBuffers[i].mData, 0, io->mBuffers[i].mDataByteSize);
    if (flags) *flags |= kAudioUnitRenderAction_OutputIsSilence;
    return noErr;
}

- (BOOL)running { return _unit != NULL; }

- (BOOL)start:(NSTimeInterval)maxSeconds {
    if (_unit) return NO;
    AudioComponentDescription d; memset(&d, 0, sizeof(d));
    d.componentType = kAudioUnitType_Output;
    d.componentSubType = kAudioUnitSubType_VoiceProcessingIO;
    d.componentManufacturer = kAudioUnitManufacturer_Apple;
    AudioComponent comp = AudioComponentFindNext(NULL, &d);
    if (!comp || AudioComponentInstanceNew(comp, &_unit) != noErr) { _unit = NULL; return NO; }

    _pcm = [[MeshPcmBuffer alloc] initWithCapacity:(NSUInteger)(maxSeconds * MeshAudioSampleRate) * 2];
    _scratch = calloc(kMaxFrames, sizeof(int16_t));
    if (!_scratch) { MeshWipe([self stop]); return NO; }

    UInt32 on = 1;
    AudioStreamBasicDescription f = MeshPcmFormat();
    AURenderCallbackStruct input = { inputCallback, (__bridge void *)self };
    AURenderCallbackStruct output = { silentOutput, NULL };
    AudioUnitSetProperty(_unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &on, sizeof(on));
    AudioUnitSetProperty(_unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &on, sizeof(on));
    AudioUnitSetProperty(_unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &f, sizeof(f));   // Mikrofon
    AudioUnitSetProperty(_unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &f, sizeof(f));    // Lautsprecher
    AudioUnitSetProperty(_unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &input, sizeof(input));
    AudioUnitSetProperty(_unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &output, sizeof(output));

    OSStatus st = AudioUnitInitialize(_unit);
    if (st == noErr) st = AudioOutputUnitStart(_unit);
    if (st != noErr) { MeshLog(@"Aufnahme: Voice-Processing starten %d", (int)st); MeshWipe([self stop]); return NO; }
    return YES;
}

- (NSMutableData *)stop {
    if (!_unit) return nil;
    AudioOutputUnitStop(_unit);        // kehrt erst zurück, wenn kein Rückruf mehr läuft
    AudioUnitUninitialize(_unit);
    AudioComponentInstanceDispose(_unit);
    _unit = NULL;
    NSMutableData *out = [_pcm take];
    _pcm = nil;
    if (_scratch) MeshWipeBytes(_scratch, kMaxFrames * sizeof(int16_t));
    free(_scratch);
    _scratch = NULL;
    return out;
}

- (void)dealloc { MeshWipe([self stop]); }

@end
