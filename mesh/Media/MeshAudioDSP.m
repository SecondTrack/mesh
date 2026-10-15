#import "MeshAudioDSP.h"
#import "MeshVoiceFX.h"
#import <Accelerate/Accelerate.h>
#import "MeshAudioCodec.h"
#import "MeshMemory.h"

NSString *const MeshEffectNone   = @"none";
NSString *const MeshEffectHigh   = @"high";
NSString *const MeshEffectDeep   = @"deep";
NSString *const MeshEffectRobot  = @"robot";
NSString *const MeshEffectAlien  = @"alien";
NSString *const MeshEffectAnonym = @"anonym";
NSString *const MeshEffectChipmunk = @"chipmunk";
NSString *const MeshEffectChipmunkAnon = @"chipmunk_anon";

#pragma mark - Hilfen

static float *floats(size_t count) { return calloc(count, sizeof(float)); }

// Alle Puffer hier tragen das Stimmsignal oder Größen daraus: vor dem Freigeben überschreiben.
static void freeWiped(float *p, size_t count) {
    if (!p) return;
    MeshWipeBytes(p, count * sizeof(float));
    free(p);
}

static int16_t clampSample(double v) {
    return (int16_t)(v > 32767 ? 32767 : (v < -32768 ? -32768 : v));
}

// Kurzzeit-FFT über Blöcke von size Samples mit Hann-Fenster: Fenster, Spektrum (re/im) und
// ein Arbeitsblock. Gemeinsam für Rauschfilter und Tonhöhenverschiebung.
typedef struct {
    int size, half, log2n;
    FFTSetup setup;
    float *window, *re, *im, *block;
    DSPSplitComplex spectrum;
} MeshStft;

static MeshStft stftCreate(int log2n) {
    MeshStft s;
    s.log2n = log2n;
    s.size = 1 << log2n;
    s.half = s.size / 2;
    s.setup = vDSP_create_fftsetup(log2n, kFFTRadix2);
    s.window = floats(s.size);
    vDSP_hann_window(s.window, s.size, vDSP_HANN_DENORM);
    s.re = floats(s.half);
    s.im = floats(s.half);
    s.block = floats(s.size);
    s.spectrum.realp = s.re;
    s.spectrum.imagp = s.im;
    return s;
}

// NO, wenn der Speicher nicht reichte; dann bleibt das Signal unverändert.
static BOOL stftUsable(const MeshStft *s) {
    return s->setup && s->window && s->re && s->im && s->block;
}

static void stftDestroy(MeshStft *s) {
    free(s->window);
    freeWiped(s->re, s->half);
    freeWiped(s->im, s->half);
    freeWiped(s->block, s->size);
    if (s->setup) vDSP_destroy_fftsetup(s->setup);
}

// Gefensterter Block ab samples → Spektrum.
static void stftForward(MeshStft *s, const float *samples) {
    vDSP_vmul(samples, 1, s->window, 1, s->block, 1, s->size);
    vDSP_ctoz((DSPComplex *)s->block, 2, &s->spectrum, 1, s->half);
    vDSP_fft_zrip(s->setup, &s->spectrum, 1, s->log2n, kFFTDirection_Forward);
}

// Spektrum → Block, mit scale skaliert.
static void stftInverse(MeshStft *s, float scale) {
    vDSP_fft_zrip(s->setup, &s->spectrum, 1, s->log2n, kFFTDirection_Inverse);
    vDSP_ztoc(&s->spectrum, 1, (DSPComplex *)s->block, 2, s->half);
    vDSP_vsmul(s->block, 1, &scale, s->block, 1, s->size);
}

// Block gefenstert bei offset in out addieren (Overlap-Add), Fensterenergie in weight.
static void stftOverlapAdd(MeshStft *s, float *out, float *weight, int offset, int length) {
    for (int k = 0; k < s->size && offset + k < length; k++) {
        out[offset + k] += s->block[k] * s->window[k];
        weight[offset + k] += s->window[k] * s->window[k];
    }
}

#pragma mark - Filter

// Rauschunterdrückung: Wiener-Filter mit decision-directed SNR-Schätzung (Ephraim-Malah).
// STFT 512/256 Hann, Rauschleistung = Minimum je Frequenz. Zeitliche Glättung des
// a-priori-SNR verhindert musical noise. strength: 1 mild … 4 sehr stark.
static void spectralWiener(float *x, int n, float strength) {
    const int hop = 256;
    const float alpha = 0.98f;
    if (n < 1024) return;
    float floorGain = fmaxf(0.18f - 0.03f * (strength - 1.0f), 0.06f);

    MeshStft s = stftCreate(9);
    int frames = (n - s.size) / hop + 1;
    float *noise = floats(s.half), *prevGain = floats(s.half), *prevSnr = floats(s.half);
    float *out = floats(n), *weight = floats(n);
    if (!stftUsable(&s) || !noise || !prevGain || !prevSnr || !out || !weight) goto done;
    for (int k = 0; k < s.half; k++) { noise[k] = 1e30f; prevGain[k] = 1; prevSnr[k] = 1; }

    for (int f = 0; f < frames; f++) {
        stftForward(&s, x + f * hop);
        for (int k = 0; k < s.half; k++) noise[k] = fminf(noise[k], s.re[k] * s.re[k] + s.im[k] * s.im[k]);
    }
    float bias = 1.5f * strength;
    for (int k = 0; k < s.half; k++) noise[k] *= bias;

    for (int f = 0; f < frames; f++) {
        stftForward(&s, x + f * hop);
        for (int k = 0; k < s.half; k++) {
            float power = s.re[k] * s.re[k] + s.im[k] * s.im[k];
            float snr = power / (noise[k] + 1e-3f);
            float prior = alpha * prevGain[k] * prevGain[k] * prevSnr[k] + (1.0f - alpha) * fmaxf(snr - 1.0f, 0.0f);
            float gain = fminf(fmaxf(prior / (1.0f + prior), floorGain), 1.0f);
            s.re[k] *= gain;
            s.im[k] *= gain;
            prevGain[k] = gain;
            prevSnr[k] = snr;
        }
        stftInverse(&s, 1.0f / (2 * s.size));
        stftOverlapAdd(&s, out, weight, f * hop, n);
    }
    for (int i = 0; i < n; i++) x[i] = weight[i] > 1e-6f ? out[i] / weight[i] : 0;

done:
    freeWiped(noise, s.half);
    freeWiped(prevGain, s.half);
    freeWiped(prevSnr, s.half);
    freeWiped(out, n);
    freeWiped(weight, n);
    stftDestroy(&s);
}

// Biquad in Transposed Direct Form II (a0 auf 1 normalisiert).
static void biquad(float *x, int n, double b0, double b1, double b2, double a1, double a2) {
    double z1 = 0, z2 = 0;
    for (int i = 0; i < n; i++) {
        double in = x[i];
        double out = b0 * in + z1;
        z1 = b1 * in - a1 * out + z2;
        z2 = b2 * in - a2 * out;
        x[i] = (float)out;
    }
}

static void highpass(float *x, int n, double cutoff) {
    double w0 = 2 * M_PI * cutoff / MeshAudioSampleRate, c = cos(w0), alpha = sin(w0) / (2 * 0.707);
    double a0 = 1 + alpha;
    biquad(x, n, (1 + c) / 2 / a0, -(1 + c) / a0, (1 + c) / 2 / a0, -2 * c / a0, (1 - alpha) / a0);
}

static void lowpass(float *x, int n, double cutoff) {
    double w0 = 2 * M_PI * cutoff / MeshAudioSampleRate, c = cos(w0), alpha = sin(w0) / (2 * 0.707);
    double a0 = 1 + alpha;
    biquad(x, n, (1 - c) / 2 / a0, (1 - c) / a0, (1 - c) / 2 / a0, -2 * c / a0, (1 - alpha) / a0);
}

static void peaking(float *x, int n, double center, double dB, double q) {
    double A = pow(10, dB / 40), w0 = 2 * M_PI * center / MeshAudioSampleRate, c = cos(w0), alpha = sin(w0) / (2 * q);
    double a0 = 1 + alpha / A;
    biquad(x, n, (1 + alpha * A) / a0, -2 * c / a0, (1 - alpha * A) / a0, -2 * c / a0, (1 - alpha / A) / a0);
}

@implementation MeshAudioDSP

+ (NSData *)process:(NSData *)pcm noise:(float)noise hp:(float)hpHz lp:(float)lpHz presence:(float)presenceDb gain:(float)gain {
    NSUInteger n = pcm.length / 2;
    if (n < 2) return pcm;
    const int16_t *in = pcm.bytes;
    double dc = 0;
    for (NSUInteger i = 0; i < n; i++) dc += in[i];
    dc /= n;
    float *x = floats(n);
    if (!x) return pcm;
    for (NSUInteger i = 0; i < n; i++) x[i] = (float)(in[i] - dc);

    if (hpHz > 20)                highpass(x, (int)n, hpHz);
    if (lpHz < 7800)              lowpass(x, (int)n, lpHz);
    if (noise > 0.1f)             spectralWiener(x, (int)n, noise);
    if (fabsf(presenceDb) > 0.3f) peaking(x, (int)n, 3000.0, presenceDb, 0.9);

    // Auf -3 dBFS normalisieren, dann Endverstärkung mit weicher Begrenzung.
    float peak = 1;
    for (NSUInteger i = 0; i < n; i++) peak = fmaxf(peak, fabsf(x[i]));
    float norm = fminf(fmaxf((0.70f * 32768.0f) / peak, 1), 15);
    NSMutableData *result = [NSMutableData dataWithLength:n * 2];
    int16_t *out = result.mutableBytes;
    for (NSUInteger i = 0; i < n; i++) {
        float v = x[i] * norm * gain;
        out[i] = (int16_t)(32767.0f * tanhf(v / 32767.0f));
    }
    freeWiped(x, n);
    return result;
}

// Weiche Sättigung (tanh) statt hartem Clipping: laut ohne Knacken.
+ (NSData *)applyGain:(NSData *)pcm factor:(double)factor {
    if (factor <= 1.001) return pcm;
    NSMutableData *result = [pcm mutableCopy];
    int16_t *s = result.mutableBytes;
    for (NSUInteger i = 0, n = result.length / 2; i < n; i++)
        s[i] = clampSample(32767.0 * tanh(s[i] * factor / 32767.0));
    return result;
}

#pragma mark - Stimmeffekte (gleiche Verfahren wie in der Android-App)

+ (NSData *)applyEffect:(NSData *)pcm effect:(NSString *)effect {
    // Rechnung 1:1 wie in der Android-App (MeshVoiceFX), damit derselbe Effekt auf beiden Geräten gleich klingt.
    // nil heißt: Effekt gescheitert -> der Aufrufer schickt dann nichts statt der echten Stimme.
    return MeshVoiceFXApply(pcm, effect ?: MeshEffectNone);
}

// Tonhöhe per Phase-Vocoder verschieben (ratio < 1 = tiefer), Tempo bleibt: erst um 1/ratio
// zeitlich dehnen, dann um ratio zurückrechnen.
+ (NSData *)pitchShift:(NSData *)pcm ratio:(float)ratio {
    NSUInteger n = pcm.length / 2;
    if (n < 2048 || ratio <= 0.1f || ratio > 4.0f) return pcm;
    const int analysisHop = 256;
    int synthesisHop = MAX(1, (int)roundf(analysisHop * (1.0f / ratio)));
    int frames = (int)((n - 1024) / analysisHop) + 1;
    if (frames < 2) return pcm;

    MeshStft s = stftCreate(10);
    int stretched = (frames - 1) * synthesisHop + s.size;
    float *x = floats(n), *out = floats(stretched), *weight = floats(stretched);
    float *lastPhase = floats(s.half), *sumPhase = floats(s.half);
    NSMutableData *result = nil;
    if (!stftUsable(&s) || !x || !out || !weight || !lastPhase || !sumPhase) goto done;
    const int16_t *in = pcm.bytes;
    for (NSUInteger i = 0; i < n; i++) x[i] = in[i];
    float expected = 2.0f * (float)M_PI * analysisHop / s.size;   // Phasenvorschub je Frequenzband

    for (int f = 0; f < frames; f++) {
        stftForward(&s, x + f * analysisHop);
        for (int k = 1; k < s.half; k++) {
            float real = s.re[k] * 0.5f, imag = s.im[k] * 0.5f;
            float magnitude = sqrtf(real * real + imag * imag);
            float phase = atan2f(imag, real);
            float delta = phase - lastPhase[k] - (float)k * expected;
            lastPhase[k] = phase;
            delta -= 2.0f * (float)M_PI * roundf(delta / (2.0f * (float)M_PI));
            sumPhase[k] += ((float)k * expected + delta) * ((float)synthesisHop / (float)analysisHop);
            s.re[k] = magnitude * cosf(sumPhase[k]);
            s.im[k] = magnitude * sinf(sumPhase[k]);
        }
        stftInverse(&s, 1.0f / s.size);
        stftOverlapAdd(&s, out, weight, f * synthesisHop, stretched);
    }
    for (int i = 0; i < stretched; i++) out[i] = weight[i] > 1e-6f ? out[i] / weight[i] : 0;

    NSUInteger length = MAX((NSUInteger)1, (NSUInteger)(stretched * ratio));
    result = [NSMutableData dataWithLength:length * 2];
    int16_t *r = result.mutableBytes;
    for (NSUInteger i = 0; i < length; i++) {
        double pos = i / ratio;
        NSUInteger j = (NSUInteger)pos;
        float a = j < (NSUInteger)stretched ? out[j] : 0;
        float b = j + 1 < (NSUInteger)stretched ? out[j + 1] : a;
        float v = a + (b - a) * (pos - j);
        r[i] = clampSample(v);
    }

done:
    freeWiped(x, n);
    freeWiped(out, stretched);
    freeWiped(weight, stretched);
    freeWiped(lastPhase, s.half);
    freeWiped(sumPhase, s.half);
    stftDestroy(&s);
    return result;
}

+ (NSMutableData *)resample:(const int16_t *)s count:(NSUInteger)n ratio:(double)ratio {
    NSUInteger length = MAX((NSUInteger)1, (NSUInteger)(n / ratio));
    NSMutableData *result = [NSMutableData dataWithLength:length * 2];
    int16_t *out = result.mutableBytes;
    for (NSUInteger i = 0; i < length; i++) {
        double pos = i * ratio;
        NSUInteger j = (NSUInteger)pos;
        int a = j < n ? s[j] : 0;
        int b = j + 1 < n ? s[j + 1] : a;
        out[i] = clampSample(a + (b - a) * (pos - j));
    }
    return result;
}

@end
