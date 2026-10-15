#import "MeshAudioCodec.h"
#import <AudioToolbox/AudioToolbox.h>
#import "MeshLog.h"
#import "MeshMemory.h"

const double MeshAudioSampleRate = 16000.0;

@implementation MeshAudioCodec

+ (NSData *)wavFromPcm:(NSData *)pcm {
    uint32_t dataLen = (uint32_t)pcm.length, sr = (uint32_t)MeshAudioSampleRate, byteRate = sr * 2;
    uint32_t riff = 36 + dataLen;
    NSMutableData *w = [NSMutableData data];
    [w appendBytes:"RIFF" length:4]; [w appendBytes:&riff length:4]; [w appendBytes:"WAVE" length:4];
    [w appendBytes:"fmt " length:4];
    uint32_t fmtLen = 16; uint16_t pcmType = 1, ch = 1, bits = 16, blockAlign = 2;
    [w appendBytes:&fmtLen length:4]; [w appendBytes:&pcmType length:2]; [w appendBytes:&ch length:2];
    [w appendBytes:&sr length:4]; [w appendBytes:&byteRate length:4]; [w appendBytes:&blockAlign length:2]; [w appendBytes:&bits length:2];
    [w appendBytes:"data" length:4]; [w appendBytes:&dataLen length:4]; [w appendData:pcm];
    return w;
}

#pragma mark - AAC (m4a) über ExtAudioFile, komplett im Speicher

// Core Audio liest und schreibt über diese Callbacks direkt in NSData. Entschlüsselte Sprachnachrichten
// und die eigene Aufnahme landen so nie als Klartext-Datei im tmp-Ordner (gelöscht wäre sie trotzdem
// noch auf dem Flash).
static const SInt64 kMaxContainerBytes = 8 << 20;

static OSStatus memRead(void *ud, SInt64 pos, UInt32 req, void *buf, UInt32 *got) {
    NSData *d = (__bridge NSData *)ud;
    *got = 0;
    if (pos < 0 || pos > (SInt64)d.length) return kAudioFileInvalidFileError;
    UInt32 n = (UInt32)MIN((SInt64)req, (SInt64)d.length - pos);
    memcpy(buf, (const char *)d.bytes + pos, n);
    *got = n;
    return noErr;
}

static OSStatus memWrite(void *ud, SInt64 pos, UInt32 req, const void *buf, UInt32 *done) {
    NSMutableData *d = (__bridge NSMutableData *)ud;
    *done = 0;
    if (pos < 0 || pos + req > kMaxContainerBytes) return kAudioFileInvalidFileError;
    if (pos + req > (SInt64)d.length) d.length = (NSUInteger)(pos + req);
    [d replaceBytesInRange:NSMakeRange((NSUInteger)pos, req) withBytes:buf];
    *done = req;
    return noErr;
}

static SInt64 memSize(void *ud) { return (SInt64)((__bridge NSData *)ud).length; }

static OSStatus memSetSize(void *ud, SInt64 size) {
    if (size < 0 || size > kMaxContainerBytes) return kAudioFileInvalidFileError;
    ((__bridge NSMutableData *)ud).length = (NSUInteger)size;
    return noErr;
}

AudioStreamBasicDescription MeshPcmFormat(void) {
    AudioStreamBasicDescription f; memset(&f, 0, sizeof(f));
    f.mFormatID = kAudioFormatLinearPCM;
    f.mSampleRate = MeshAudioSampleRate;
    f.mChannelsPerFrame = 1;
    f.mBitsPerChannel = 16;
    f.mFramesPerPacket = 1;
    f.mBytesPerFrame = 2;
    f.mBytesPerPacket = 2;
    f.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    return f;
}

#pragma mark - M4A verdichten

// Core Audio legt vor mdat einen free-Block von ~24 KB an (Platz für ein späteres moov) und schreibt
// in moov/udta Encoder-Angaben. Für eine 3-s-Sprachnachricht sind das 30 KB statt 6 KB – über Relays mit
// 128-KB-Grenze (nos.lol, nostr.mom) zu viel. Neu verpackt als ftyp + moov (ohne udta) + mdat; die
// Chunk-Offsets (stco/co64) werden um die Verschiebung von mdat korrigiert. Passt etwas nicht: nil.
static uint32_t rd32(const uint8_t *p) { return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3]; }
static void wr32(uint8_t *p, uint32_t v) { p[0] = v >> 24; p[1] = v >> 16; p[2] = v >> 8; p[3] = v; }

// Box bei off innerhalb [off, end): Größe und Kopf. NO bei kaputten Größen (auch 64-Bit-Größen: kommen hier nicht vor).
static BOOL boxAt(const uint8_t *b, NSUInteger off, NSUInteger end, NSUInteger *size, const uint8_t **type) {
    if (end - off < 8) return NO;
    NSUInteger s = rd32(b + off);
    if (s < 8 || s > end - off) return NO;
    *size = s; *type = b + off + 4;
    return YES;
}

// Offsets in stco/co64 innerhalb von [off, end) um delta verschieben; jeder alte Offset muss in mdat liegen.
static BOOL fixOffsets(uint8_t *b, NSUInteger off, NSUInteger end, long long delta, uint64_t lo, uint64_t hi) {
    while (off < end) {
        NSUInteger size; const uint8_t *t;
        if (!boxAt(b, off, end, &size, &t)) return NO;
        if (!memcmp(t, "trak", 4) || !memcmp(t, "mdia", 4) || !memcmp(t, "minf", 4) || !memcmp(t, "stbl", 4)) {
            if (!fixOffsets(b, off + 8, off + size, delta, lo, hi)) return NO;
        } else if (!memcmp(t, "stco", 4) || !memcmp(t, "co64", 4)) {
            BOOL wide = t[1] == 'o';
            if (size < 16) return NO;
            uint32_t n = rd32(b + off + 12);
            NSUInteger w = wide ? 8 : 4;
            if (n > (size - 16) / w) return NO;
            for (uint32_t k = 0; k < n; k++) {
                uint8_t *e = b + off + 16 + k * w;
                uint64_t v = wide ? ((uint64_t)rd32(e) << 32) | rd32(e + 4) : rd32(e);
                if (v < lo || v >= hi) return NO;
                uint64_t nv = (uint64_t)((long long)v + delta);
                if (wide) { wr32(e, (uint32_t)(nv >> 32)); wr32(e + 4, (uint32_t)nv); }
                else { if (nv > UINT32_MAX) return NO; wr32(e, (uint32_t)nv); }
            }
        }
        off += size;
    }
    return YES;
}

NSData *MeshCompactM4A(NSData *m4a) {
    const uint8_t *b = m4a.bytes; NSUInteger n = m4a.length, off = 0;
    NSRange ftyp = {NSNotFound, 0}, moov = {NSNotFound, 0}, mdat = {NSNotFound, 0};
    while (off < n) {
        NSUInteger size; const uint8_t *t;
        if (!boxAt(b, off, n, &size, &t)) return nil;
        NSRange r = NSMakeRange(off, size);
        if (!memcmp(t, "ftyp", 4) && ftyp.location == NSNotFound) ftyp = r;
        else if (!memcmp(t, "moov", 4) && moov.location == NSNotFound) moov = r;
        else if (!memcmp(t, "mdat", 4) && mdat.location == NSNotFound) mdat = r;
        else if (memcmp(t, "free", 4) && memcmp(t, "skip", 4) && memcmp(t, "wide", 4)) return nil;   // Unbekanntes: nicht anfassen
        off += size;
    }
    if (ftyp.location != 0 || moov.location == NSNotFound || mdat.location == NSNotFound) return nil;
    // moov ohne udta
    NSMutableData *mv = [NSMutableData dataWithBytes:b + moov.location length:8];
    for (NSUInteger o = moov.location + 8, end = NSMaxRange(moov); o < end;) {
        NSUInteger size; const uint8_t *t;
        if (!boxAt(b, o, end, &size, &t)) return nil;
        if (memcmp(t, "udta", 4)) [mv appendBytes:b + o length:size];
        o += size;
    }
    wr32(mv.mutableBytes, (uint32_t)mv.length);
    long long delta = (long long)(ftyp.length + mv.length) - (long long)mdat.location;
    if (!fixOffsets(mv.mutableBytes, 8, mv.length, delta, mdat.location + 8, NSMaxRange(mdat))) return nil;
    NSMutableData *out = [NSMutableData dataWithCapacity:ftyp.length + mv.length + mdat.length];
    [out appendBytes:b length:ftyp.length];
    [out appendData:mv];
    [out appendBytes:b + mdat.location length:mdat.length];
    return out;
}

+ (NSData *)pcmToAac:(NSData *)pcm {
    AudioStreamBasicDescription dst; memset(&dst, 0, sizeof(dst));
    dst.mFormatID = kAudioFormatMPEG4AAC;
    dst.mSampleRate = MeshAudioSampleRate;
    dst.mChannelsPerFrame = 1;
    UInt32 sz = sizeof(dst);
    AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &sz, &dst);   // Rest der Beschreibung ergänzen

    // Platz vorab, damit der Puffer beim Schreiben möglichst nicht umzieht und Kopien zurücklässt
    // (AAC mit 24 kbit/s ist rund zehnmal kleiner als das PCM). Die Länge setzt Core Audio selbst.
    NSMutableData *out = [NSMutableData dataWithCapacity:pcm.length / 4];
    AudioFileID af = NULL;
    OSStatus st = AudioFileInitializeWithCallbacks((__bridge void *)out, memRead, memWrite, memSize, memSetSize,
                                                   kAudioFileM4AType, &dst, 0, &af);
    if (st != noErr || !af) { MeshLog(@"Sprache: AudioFileInitialize fehlgeschlagen (%d)", (int)st); return nil; }
    ExtAudioFileRef ef = NULL;
    st = ExtAudioFileWrapAudioFileID(af, true, &ef);
    if (st != noErr || !ef) { MeshLog(@"Sprache: ExtAudioFileWrap fehlgeschlagen (%d)", (int)st); AudioFileClose(af); return nil; }

    AudioStreamBasicDescription client = MeshPcmFormat();
    st = ExtAudioFileSetProperty(ef, kExtAudioFileProperty_ClientDataFormat, sizeof(client), &client);

    // Bitrate explizit niedrig halten (sonst 64-128 kbps Default -> Events zu groß fürs Relay).
    AudioConverterRef conv = NULL; UInt32 csz = sizeof(conv);
    if (st == noErr && ExtAudioFileGetProperty(ef, kExtAudioFileProperty_AudioConverter, &csz, &conv) == noErr && conv) {
        UInt32 br = 24000;
        AudioConverterSetProperty(conv, kAudioConverterEncodeBitRate, sizeof(br), &br);
        CFArrayRef cfg = NULL;   // ExtAudioFile über die Converter-Änderung informieren
        ExtAudioFileSetProperty(ef, kExtAudioFileProperty_ConverterConfig, sizeof(cfg), &cfg);
    }

    if (st == noErr) {
        AudioBufferList abl;
        abl.mNumberBuffers = 1;
        abl.mBuffers[0].mNumberChannels = 1;
        abl.mBuffers[0].mDataByteSize = (UInt32)pcm.length;
        abl.mBuffers[0].mData = (void *)pcm.bytes;
        st = ExtAudioFileWrite(ef, (UInt32)(pcm.length / 2), &abl);
    }
    ExtAudioFileDispose(ef);
    AudioFileClose(af);   // schreibt erst hier den moov-Block
    if (st != noErr) { MeshLog(@"Sprache: AAC-Kodierung fehlgeschlagen (%d)", (int)st); return nil; }
    if (!out.length) return nil;
    NSData *compact = MeshCompactM4A(out);
    if (compact) MeshWipe(out);   // die alte Kopie mit dem Signal nicht liegen lassen
    return compact ?: out;
}

+ (NSData *)aacToPcm:(NSData *)aac maxSeconds:(NSTimeInterval)maxSeconds {
    // Mesh (iOS und Android) schickt M4A, ältere Nachrichten können rohes ADTS sein.
    NSUInteger maxBytes = (NSUInteger)(maxSeconds * MeshAudioSampleRate * 2);
    for (NSNumber *type in @[@(kAudioFileM4AType), @(kAudioFileAAC_ADTSType)]) {
        NSData *pcm = [self decode:aac type:(AudioFileTypeID)type.unsignedIntValue maxBytes:maxBytes];
        if (pcm.length) return pcm;
    }
    return nil;
}

// maxBytes schützt vor Dekompressionsbomben: winzige AAC-Frames ergeben sonst Hunderte MB PCM.
+ (NSData *)decode:(NSData *)aac type:(AudioFileTypeID)type maxBytes:(NSUInteger)maxBytes {
    AudioFileID af = NULL;
    if (AudioFileOpenWithCallbacks((__bridge void *)aac, memRead, NULL, memSize, NULL, type, &af) != noErr || !af) return nil;
    ExtAudioFileRef ef = NULL;
    if (ExtAudioFileWrapAudioFileID(af, false, &ef) != noErr || !ef) { AudioFileClose(af); return nil; }
    AudioStreamBasicDescription client = MeshPcmFormat();
    ExtAudioFileSetProperty(ef, kExtAudioFileProperty_ClientDataFormat, sizeof(client), &client);
    NSMutableData *buffer = [NSMutableData dataWithLength:maxBytes];   // feste Größe: zieht nicht um
    NSUInteger filled = 0;
    const UInt32 cap = 4096;
    int16_t *tmp = malloc(cap * 2);
    while (tmp && buffer) {
        AudioBufferList abl; abl.mNumberBuffers = 1; abl.mBuffers[0].mNumberChannels = 1;
        abl.mBuffers[0].mDataByteSize = cap * 2; abl.mBuffers[0].mData = tmp;
        UInt32 got = cap;
        if (ExtAudioFileRead(ef, &got, &abl) != noErr || got == 0) break;
        if (filled + got * 2 > maxBytes) break;
        memcpy((char *)buffer.mutableBytes + filled, tmp, got * 2);
        filled += got * 2;
    }
    if (tmp) MeshWipeBytes(tmp, cap * 2);
    free(tmp);
    ExtAudioFileDispose(ef);
    AudioFileClose(af);
    NSMutableData *out = [NSMutableData dataWithBytes:buffer.bytes length:filled];
    MeshWipe(buffer);
    return out;
}

@end
