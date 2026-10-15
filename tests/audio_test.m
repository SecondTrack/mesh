// MeshAudioCodec und MeshAudioDSP: Rundwege, Längen, Pegel.
#import "MeshTest.h"
#include <math.h>
#import "MeshAudioCodec.h"
#import "MeshAudioDSP.h"
#import "MeshPcmBuffer.h"
#import "MeshMediaCheck.h"

static NSData *sine(double hz, double seconds, double amp) {
    NSUInteger n = (NSUInteger)(MeshAudioSampleRate * seconds);
    NSMutableData *d = [NSMutableData dataWithLength:n * 2];
    int16_t *s = d.mutableBytes;
    for (NSUInteger i = 0; i < n; i++) s[i] = (int16_t)(amp * sin(2 * M_PI * hz * i / MeshAudioSampleRate));
    return d;
}
static int peak(NSData *pcm) {
    const int16_t *s = pcm.bytes; int p = 0;
    for (NSUInteger i = 0; i < pcm.length / 2; i++) { int a = abs(s[i]); if (a > p) p = a; }
    return p;
}
static BOOL near(double a, double b, double tol) { return fabs(a - b) <= tol * b; }

int main(void) { @autoreleasepool {
    NSData *tone = sine(440, 2.0, 8000);
    NSUInteger n = tone.length / 2;

    // WAV
    NSData *wav = [MeshAudioCodec wavFromPcm:tone];
    check(wav.length == tone.length + 44 && !memcmp(wav.bytes, "RIFF", 4), "wav header");
    check([[wav subdataWithRange:NSMakeRange(44, tone.length)] isEqual:tone], "wav carries pcm");

    NSArray *tmpBefore = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:NSTemporaryDirectory() error:NULL];
    // AAC: klein, Länge und Pegel bleiben ungefähr erhalten
    NSData *aac = [MeshAudioCodec pcmToAac:tone];
    check(aac.length > 0 && aac.length < tone.length / 2, "aac compresses");
    check([MeshMediaCheck isAcceptableAudio:aac], "own m4a passes structure check");
    NSData *back = [MeshAudioCodec aacToPcm:aac maxSeconds:60];
    check(near(back.length / 2, n, 0.1), "aac roundtrip length");
    check(near(peak(back), 8000, 0.25), "aac roundtrip level");
    check([MeshAudioCodec aacToPcm:aac maxSeconds:0.5].length <= MeshAudioSampleRate * 2 * 0.5, "decode stops at limit");
    NSArray *tmpAfter = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:NSTemporaryDirectory() error:NULL];
    check([[NSSet setWithArray:tmpAfter] isEqualToSet:[NSSet setWithArray:tmpBefore]], "no plaintext temp files");
    NSMutableData *junk = [NSMutableData dataWithLength:4096];
    arc4random_buf(junk.mutableBytes, junk.length);
    check([MeshAudioCodec aacToPcm:junk maxSeconds:60] == nil, "garbage rejected");
    check([MeshAudioCodec aacToPcm:[aac subdataWithRange:NSMakeRange(0, aac.length / 3)] maxSeconds:60].length < back.length,
          "truncated m4a does not crash");

    // Verdichtet: kein free-Polster, kein udta, Offsets stimmen (dekodiert gleich lang)
    check(memmem(aac.bytes, aac.length, "free", 4) == NULL && memmem(aac.bytes, aac.length, "udta", 4) == NULL, "m4a compacted");
    check(aac.length < 12000, "3 s tone well under 12 KB");
    check(MeshCompactM4A(aac) != nil && [MeshCompactM4A(aac) isEqual:aac], "compaction idempotent");
    check(MeshCompactM4A(junk) == nil, "compaction rejects garbage");

    // Android (Voice.kt bis 2026-10): rohes ADTS, Kopf FF F9 (MPEG-2, AAC-LC, 16 kHz, mono) – mit
    // afconvert erzeugt und mit exakt Androids addAdts-Köpfen neu verpackt (tests/fixtures).
    NSData *android = [NSData dataWithContentsOfFile:@"tests/fixtures/android_voice.aac"];
    check(android.length > 0 && ((const uint8_t *)android.bytes)[1] == 0xF9, "android fixture present");
    check([MeshMediaCheck isAcceptableAudio:android], "android adts passes structure check");
    NSData *apcm = [MeshAudioCodec aacToPcm:android maxSeconds:60];
    check(near(apcm.length / 2, 3 * MeshAudioSampleRate, 0.1) && peak(apcm) > 4000, "android adts decodes");

    // Effekte: Tonhöhe über Resampling ändert die Länge, Anonymisieren nicht
    // Wie in der Android-App: jeder Effekt behält die Länge exakt und verändert das Signal
    check([[MeshAudioDSP applyEffect:tone effect:@"none"] isEqual:tone], "none unchanged");
    for (NSString *fx in @[@"anonym", @"high", @"chipmunk", @"chipmunk_anon", @"deep", @"robot", @"alien"]) {
        NSData *o = [MeshAudioDSP applyEffect:tone effect:fx];
        check(o.length == tone.length, [[fx stringByAppendingString:@" keeps length"] UTF8String]);
        check(o && ![o isEqual:tone], [[fx stringByAppendingString:@" changes signal"] UTF8String]);
    }

    // Aufbereitung: gleiche Länge, auf ~-3 dBFS normalisiert, Tiefpass dämpft hohe Töne
    NSData *proc = [MeshAudioDSP process:tone noise:0 hp:90 lp:7000 presence:0 gain:1];
    check(proc.length == tone.length, "process keeps length");
    check(near(peak(proc), 0.70 * 32768 * tanh(0.70 * 32768 / 32767.0) / (0.70 * 32768 / 32767.0), 0.08), "process normalizes");
    NSData *hi = [MeshAudioDSP process:sine(7600, 1.0, 8000) noise:0 hp:20 lp:2000 presence:0 gain:1];
    NSData *lo = [MeshAudioDSP process:sine(400, 1.0, 8000) noise:0 hp:20 lp:2000 presence:0 gain:1];
    check(peak(hi) <= peak(lo) * 1.01, "lowpass + normalize stay bounded");
    check([MeshAudioDSP process:sine(440, 1.0, 8000) noise:2 hp:90 lp:7000 presence:3 gain:1].length == 32000, "denoise path runs");

    // Verstärkung: Faktor ≤ 1 lässt unverändert, Soft-Limiter clippt nie hart
    check([[MeshAudioDSP applyGain:tone factor:1.0] isEqual:tone], "gain 1 unchanged");
    check(peak([MeshAudioDSP applyGain:sine(440, 0.5, 30000) factor:3.6]) < 32767, "soft limiter");

    // Aufnahmepuffer: feste Größe, Obergrenze, nach take leer
    MeshPcmBuffer *buf = [[MeshPcmBuffer alloc] initWithCapacity:6];
    [buf append:"abcd" length:4];
    [buf append:"efgh" length:4];
    NSMutableData *took = [buf take];
    check([took isEqualToData:[NSData dataWithBytes:"abcdef" length:6]], "buffer stops at capacity");
    check([buf take].length == 0, "buffer empty after take");

    return testsDone();
}}
