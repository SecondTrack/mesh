// MeshVoiceFX — Stimmeffekte als 1:1-Übertragung der Android-App (de/mesh/app/data/Voice.kt, applyEffect),
// damit eine Sprachnachricht mit demselben Effekt auf iPod und Android gleich klingt.
// Gleiche Rechnung, gleiche Konstanten (FFT 1024, Hop 256, Cepstrum-Lifter 30), gleiche Faktoren und gleicher
// Zufall pro Nachricht; nur die Sprache ist eine andere (C statt Kotlin). Eingabe/Ausgabe: PCM16 mono, Länge gleich.
#import "MeshVoiceFX.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>

#define N      1024
#define HOP    256
#define LIFTER 30

static double gHann[N];
static void initHann(void) {
    static int done = 0;
    if (done) return;
    for (int i = 0; i < N; i++) gHann[i] = 0.5 - 0.5 * cos(2.0 * M_PI * i / (N - 1));
    done = 1;
}

static double rnd(void) { return arc4random_uniform(1u << 30) / (double)(1u << 30); }   // [0,1) wie Random.nextDouble()

// In-place Radix-2-FFT; inverse = IFFT inkl. 1/n
static void fft(double *re, double *im, int n, int inverse) {
    int j = 0;
    for (int i = 1; i < n; i++) {
        int bit = n >> 1;
        while (j & bit) { j ^= bit; bit >>= 1; }
        j |= bit;
        if (i < j) { double tr = re[i]; re[i] = re[j]; re[j] = tr; double ti = im[i]; im[i] = im[j]; im[j] = ti; }
    }
    for (int len = 2; len <= n; len <<= 1) {
        double ang = (inverse ? 2.0 : -2.0) * M_PI / len, wr = cos(ang), wi = sin(ang);
        for (int i = 0; i < n; i += len) {
            double curR = 1.0, curI = 0.0;
            int half = len / 2;
            for (int k = 0; k < half; k++) {
                double tr = re[i + k + half] * curR - im[i + k + half] * curI;
                double ti = re[i + k + half] * curI + im[i + k + half] * curR;
                double aR = re[i + k], aI = im[i + k];
                re[i + k] = aR + tr; im[i + k] = aI + ti;
                re[i + k + half] = aR - tr; im[i + k + half] = aI - ti;
                double ncurR = curR * wr - curI * wi; curI = curR * wi + curI * wr; curR = ncurR;
            }
        }
    }
    if (inverse) { double inv = 1.0 / n; for (int i = 0; i < n; i++) { re[i] *= inv; im[i] *= inv; } }
}

// Glatte Spektralhülle (Formanten) über Cepstrum-Liftering
static void envelope(const double *mag, double *env) {
    double cre[N], cim[N];
    for (int i = 0; i < N; i++) { cre[i] = log(mag[i] + 1e-6); cim[i] = 0.0; }
    fft(cre, cim, N, 1);
    for (int i = LIFTER + 1; i < N - LIFTER; i++) cre[i] = 0.0;
    for (int i = 0; i < N; i++) cim[i] = 0.0;
    fft(cre, cim, N, 0);
    for (int i = 0; i < N; i++) env[i] = exp(cre[i]);
}

// Magnitudenspektrum entlang der Frequenz um factor skalieren
static void warp(const double *src, double factor, double *out) {
    int half = N / 2;
    for (int k = 0; k <= half; k++) {
        double x = k / factor;
        if (x <= 0.0) out[k] = src[0];
        else if (x >= half) out[k] = src[half];
        else { int jj = (int)x; double f = x - jj; out[k] = src[jj] * (1 - f) + src[jj + 1] * f; }
    }
    for (int k = half + 1; k < N; k++) out[k] = out[N - k];
}

static short clip16(double v) {
    long x = (long)v;                   // wie Kotlin toInt(): Richtung 0
    if (x < -32768) x = -32768; if (x > 32767) x = 32767;
    return (short)x;
}

static double matchGainFactor(const short *src, const double *out, int len) {
    double inSq = 0, outSq = 0;
    for (int i = 0; i < len; i++) { inSq += (double)src[i] * src[i]; outSq += out[i] * out[i]; }
    if (outSq <= 1e-6) return 1.0;
    double g = sqrt(inSq / outSq);
    return g < 0.1 ? 0.1 : g > 8.0 ? 8.0 : g;
}

// Tonhöhe um pitch, Formanten um formant verschieben; whisper: Anregung durch Rauschen ersetzt
static NSData *spectralAnon(NSData *pcm, double pitch, double formant, int whisper) {
    const short *s = pcm.bytes; int len = (int)(pcm.length / 2);
    int total = len + N;
    double *padded = calloc(total, sizeof(double)), *out = calloc(total, sizeof(double)), *winSum = calloc(total, sizeof(double));
    if (!padded || !out || !winSum) { free(padded); free(out); free(winSum); return nil; }
    for (int i = 0; i < len; i++) padded[i] = s[i];
    double re[N], im[N], mag[N], ph[N], env[N], wForm[N], whit[N], wPitch[N], rp[N];
    int half = N / 2;
    for (int pos = 0; pos + N <= total; pos += HOP) {
        for (int i = 0; i < N; i++) { re[i] = padded[pos + i] * gHann[i]; im[i] = 0.0; }
        fft(re, im, N, 0);
        for (int k = 0; k < N; k++) { mag[k] = hypot(re[k], im[k]); ph[k] = atan2(im[k], re[k]); }
        envelope(mag, env);
        warp(env, formant, wForm);
        if (whisper) {
            for (int k = 0; k <= half; k++) rp[k] = (rnd() * 2.0 - 1.0) * M_PI;
            rp[0] = 0.0; rp[half] = 0.0;
            for (int k = half + 1; k < N; k++) rp[k] = -rp[N - k];
            for (int k = 0; k < N; k++) { double m = wForm[k]; re[k] = m * cos(rp[k]); im[k] = m * sin(rp[k]); }
        } else {
            for (int k = 0; k < N; k++) whit[k] = mag[k] / (env[k] + 1e-6);
            warp(whit, pitch, wPitch);
            for (int k = 0; k < N; k++) { double m = wPitch[k] * wForm[k]; re[k] = m * cos(ph[k]); im[k] = m * sin(ph[k]); }
        }
        fft(re, im, N, 1);
        for (int i = 0; i < N; i++) { out[pos + i] += re[i] * gHann[i]; winSum[pos + i] += gHann[i] * gHann[i]; }
    }
    for (int i = 0; i < len; i++) if (winSum[i] > 1e-6) out[i] /= winSum[i];
    double g = matchGainFactor(s, out, len);
    NSMutableData *res = [NSMutableData dataWithLength:(NSUInteger)len * 2];
    short *r = res.mutableBytes;
    for (int i = 0; i < len; i++) r[i] = clip16(out[i] * g);
    free(padded); free(out); free(winSum);
    return res;
}

// Phase-Vocoder-Zeitdehnung um alpha (Länge * alpha, Tonhöhe gleich); *outLen = Länge des Ergebnisses
static double *timeStretch(const double *x, int xlen, double alpha, int *outLen) {
    int syn = N / 4;
    int ana = (int)floor(syn / alpha + 0.5); if (ana < 1) ana = 1;   // Kotlin roundToInt: halbe Werte nach oben
    int frames = xlen >= N ? (xlen - N) / ana + 1 : 1;
    int olen = (frames - 1) * syn + N;
    double *out = calloc(olen, sizeof(double)), *winSum = calloc(olen, sizeof(double));
    if (!out || !winSum) { free(out); free(winSum); return NULL; }
    double re[N], im[N], mag[N], ph[N], prev[N], sum[N];
    memset(prev, 0, sizeof prev); memset(sum, 0, sizeof sum);
    for (int f = 0; f < frames; f++) {
        int base = f * ana;
        for (int i = 0; i < N; i++) { int idx = base + i; re[i] = (idx < xlen ? x[idx] : 0.0) * gHann[i]; im[i] = 0.0; }
        fft(re, im, N, 0);
        for (int k = 0; k < N; k++) { mag[k] = hypot(re[k], im[k]); ph[k] = atan2(im[k], re[k]); }
        for (int k = 0; k < N; k++) {
            double omega = 2.0 * M_PI * k / N;
            double d = ph[k] - prev[k] - omega * ana;
            d -= 2.0 * M_PI * floor(d / (2.0 * M_PI) + 0.5);    // genau wie Javas Math.round (halbe Werte nach oben)
            sum[k] += syn * (omega + d / ana);
            prev[k] = ph[k];
            re[k] = mag[k] * cos(sum[k]); im[k] = mag[k] * sin(sum[k]);
        }
        fft(re, im, N, 1);
        int ob = f * syn;
        for (int i = 0; i < N; i++) { out[ob + i] += re[i] * gHann[i]; winSum[ob + i] += gHann[i] * gHann[i]; }
    }
    for (int i = 0; i < olen; i++) if (winSum[i] > 1e-6) out[i] /= winSum[i];
    free(winSum);
    *outLen = olen;
    return out;
}

// Saubere Tonhöhenverschiebung um ratio ohne Tempoänderung (Zeitdehnung + Resampling)
static NSData *pitchShift(NSData *pcm, double ratio) {
    const short *s = pcm.bytes; int len = (int)(pcm.length / 2);
    double *x = malloc(sizeof(double) * (len > 0 ? len : 1));
    if (!x) return nil;
    for (int i = 0; i < len; i++) x[i] = s[i];
    int slen = 0;
    double *st = timeStretch(x, len, ratio, &slen);
    free(x);
    if (!st) return nil;
    double *res = malloc(sizeof(double) * (len > 0 ? len : 1));
    if (!res) { free(st); return nil; }
    for (int i = 0; i < len; i++) {
        double pos = i * ratio; int j = (int)pos; double fr = pos - j;
        double a = j < slen ? st[j] : 0.0;
        double b = j + 1 < slen ? st[j + 1] : a;
        res[i] = a + (b - a) * fr;
    }
    free(st);
    double g = matchGainFactor(s, res, len);
    NSMutableData *outD = [NSMutableData dataWithLength:(NSUInteger)len * 2];
    short *r = outD.mutableBytes;
    for (int i = 0; i < len; i++) r[i] = clip16(res[i] * g);
    free(res);
    return outD;
}

// Roboter: STFT, Phase auf 0
static NSData *robotize(NSData *pcm) {
    const short *s = pcm.bytes; int len = (int)(pcm.length / 2);
    int total = len + N;
    double *padded = calloc(total, sizeof(double)), *out = calloc(total, sizeof(double)), *winSum = calloc(total, sizeof(double));
    if (!padded || !out || !winSum) { free(padded); free(out); free(winSum); return nil; }
    for (int i = 0; i < len; i++) padded[i] = s[i];
    double re[N], im[N];
    for (int pos = 0; pos + N <= total; pos += HOP) {
        for (int i = 0; i < N; i++) { re[i] = padded[pos + i] * gHann[i]; im[i] = 0.0; }
        fft(re, im, N, 0);
        for (int k = 0; k < N; k++) { re[k] = hypot(re[k], im[k]); im[k] = 0.0; }
        fft(re, im, N, 1);
        for (int i = 0; i < N; i++) { out[pos + i] += re[i] * gHann[i]; winSum[pos + i] += gHann[i] * gHann[i]; }
    }
    for (int i = 0; i < len; i++) out[i] = winSum[i] > 1e-6 ? out[i] / winSum[i] : out[i];
    double g = matchGainFactor(s, out, len);
    NSMutableData *res = [NSMutableData dataWithLength:(NSUInteger)len * 2];
    short *r = res.mutableBytes;
    for (int i = 0; i < len; i++) r[i] = clip16(out[i] * g);
    free(padded); free(out); free(winSum);
    return res;
}

NSData *MeshVoiceFXApply(NSData *pcm, NSString *effect) {
    if (pcm.length < 4 || !effect.length || [effect isEqualToString:@"none"]) return pcm;
    initHann();
    if ([effect isEqualToString:@"high"])     return pitchShift(pcm, 1.25);
    if ([effect isEqualToString:@"deep"])     return pitchShift(pcm, 0.80);
    if ([effect isEqualToString:@"chipmunk"]) return pitchShift(pcm, 1.6);
    if ([effect isEqualToString:@"chipmunk_anon"]) {
        NSData *p = pitchShift(pcm, 1.5);
        return p ? spectralAnon(p, 1.0, 1.12 + rnd() * 0.22, 0) : nil;
    }
    if ([effect isEqualToString:@"alien"]) {
        NSData *p = pitchShift(pcm, 1.5);
        return p ? spectralAnon(p, 1.0, 0.62, 0) : nil;
    }
    if ([effect isEqualToString:@"robot"]) return robotize(pcm);
    if ([effect isEqualToString:@"anonym"]) {
        double formant = (arc4random_uniform(2) == 1) ? 1.10 + rnd() * 0.16 : 0.76 + rnd() * 0.14;
        return spectralAnon(pcm, 1.0, formant, 1);
    }
    return pcm;
}
