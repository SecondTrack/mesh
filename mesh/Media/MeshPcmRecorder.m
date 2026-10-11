#import "MeshPcmRecorder.h"
#import <AudioToolbox/AudioToolbox.h>
#import "MeshAudioCodec.h"
#import "MeshLog.h"
#import "MeshMemory.h"
#import "MeshPcmBuffer.h"

static const int kBuffers = 3;
static const UInt32 kBufferBytes = 3200;   // 100 ms

@implementation MeshPcmRecorder {
    AudioQueueRef _queue;
    AudioQueueBufferRef _buffers[kBuffers];   // vor dem Freigeben überschreiben: enthalten Stimme
    MeshPcmBuffer *_pcm;      // der Rückruf läuft auf einem Audio-Thread
    volatile BOOL _stopping;
}

static void inputCallback(void *ref, AudioQueueRef q, AudioQueueBufferRef buf, const AudioTimeStamp *t,
                          UInt32 packets, const AudioStreamPacketDescription *desc) {
    MeshPcmRecorder *self = (__bridge MeshPcmRecorder *)ref;
    [self->_pcm append:buf->mAudioData length:buf->mAudioDataByteSize];
    if (!self->_stopping) AudioQueueEnqueueBuffer(q, buf, 0, NULL);
}

- (BOOL)running { return _queue != NULL; }

- (BOOL)start:(NSTimeInterval)maxSeconds {
    if (_queue) return NO;
    _pcm = [[MeshPcmBuffer alloc] initWithCapacity:(NSUInteger)(maxSeconds * MeshAudioSampleRate) * 2];
    _stopping = NO;
    AudioStreamBasicDescription f = MeshPcmFormat();
    OSStatus st = AudioQueueNewInput(&f, inputCallback, (__bridge void *)self, NULL, NULL, 0, &_queue);
    if (st != noErr) { MeshLog(@"Aufnahme: AudioQueue anlegen %d", (int)st); _queue = NULL; return NO; }
    for (int i = 0; i < kBuffers; i++) {
        _buffers[i] = NULL;
        if (AudioQueueAllocateBuffer(_queue, kBufferBytes, &_buffers[i]) == noErr) AudioQueueEnqueueBuffer(_queue, _buffers[i], 0, NULL);
    }
    st = AudioQueueStart(_queue, NULL);
    if (st != noErr) { MeshLog(@"Aufnahme: AudioQueue starten %d", (int)st); [self stop]; return NO; }
    return YES;
}

- (NSMutableData *)stop {
    if (!_queue) return nil;
    _stopping = YES;
    AudioQueueStop(_queue, true);      // wartet, bis die letzten Puffer zurück sind
    for (int i = 0; i < kBuffers; i++)
        if (_buffers[i]) MeshWipeBytes(_buffers[i]->mAudioData, _buffers[i]->mAudioDataBytesCapacity);
    AudioQueueDispose(_queue, true);
    _queue = NULL;
    NSMutableData *out = [_pcm take];
    _pcm = nil;
    return out;
}

- (void)dealloc { MeshWipe([self stop]); }

@end
