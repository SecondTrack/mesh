#import "MeshMP4Sanitize.h"

// ---- Grenzen ----
enum { kMaxInput = 8 * 1024 * 1024,   /* Dateien in Mesh: höchstens 700 kB Inhalt; Spielraum, aber kein Speicher-Risiko am 256-MB-iPod */
        kMaxSamples = 20000, kMaxSide = 1920, kMaxDepth = 10 };
static const uint64_t kMaxSeconds = 600;

#define FOURCC(a,b,c,d) ((uint32_t)(a) << 24 | (uint32_t)(b) << 16 | (uint32_t)(c) << 8 | (uint32_t)(d))

typedef struct { const uint8_t *p; size_t n; } Span;

static uint16_t rd16(const uint8_t *p) { return (uint16_t)(p[0] << 8 | p[1]); }
static uint32_t rd32(const uint8_t *p) { return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 | (uint32_t)p[2] << 8 | p[3]; }
static uint64_t rd64(const uint8_t *p) { return (uint64_t)rd32(p) << 32 | rd32(p + 4); }

// Kind-Box `type` direkt in `in` suchen (nur eine Ebene). Prüft jede Größenangabe. Fehlerhafte Struktur: ok=0.
static int findBox(Span in, uint32_t type, Span *out, int *ok) {
    size_t o = 0;
    while (o < in.n) {
        if (in.n - o < 8) { *ok = 0; return 0; }
        uint64_t sz = rd32(in.p + o); uint32_t t = rd32(in.p + o + 4); size_t h = 8;
        if (sz == 1) { if (in.n - o < 16) { *ok = 0; return 0; } sz = rd64(in.p + o + 8); h = 16; }
        else if (sz == 0) sz = in.n - o;
        if (sz < h || sz > in.n - o) { *ok = 0; return 0; }
        if (t == type) { out->p = in.p + o + h; out->n = (size_t)sz - h; return 1; }
        o += (size_t)sz;
    }
    return 0;
}
// genau ein Vorkommen verlangt
static int needBox(Span in, uint32_t type, Span *out) { int ok = 1; return findBox(in, type, out, &ok) && ok; }

typedef struct {
    uint32_t handler;                 // 'vide' / 'soun'
    uint32_t timescale; uint64_t duration;
    uint16_t width, height;           // Video
    uint32_t matrix[9]; int hasMatrix;  // Drehung aus tkhd (nur 0/90/180/270 Grad)
    uint16_t channels; uint32_t rate; // Audio
    Span config;                      // avcC- bzw. esds-Inhalt (geprüft)
    uint32_t nSamples;
    uint32_t *sizes; uint64_t *offsets;
    uint32_t *sttsCount, *sttsDelta; uint32_t nStts;
    uint32_t *cttsCount, *cttsOff; uint32_t nCtts; uint8_t cttsVer;
    uint32_t *stss; uint32_t nStss;
} Track;

static void freeTrack(Track *t) {
    free(t->sizes); free(t->offsets); free(t->sttsCount); free(t->sttsDelta);
    free(t->cttsCount); free(t->cttsOff); free(t->stss); memset(t, 0, sizeof *t);
}

// ---- Codec-Konfiguration prüfen ----
static int checkAvcC(Span c) {
    if (c.n < 7 || c.n > 1024 || c.p[0] != 1) return 0;
    uint8_t profile = c.p[1];
    if (profile != 66 && profile != 77 && profile != 88 && profile != 100) return 0;   // Baseline, Main, Extended, High
    if ((c.p[4] & 3) != 3) return 0;                     // NAL-Längen mit 4 Byte
    size_t o = 5; int nsps = c.p[o++] & 0x1f;
    if (nsps < 1 || nsps > 2) return 0;
    for (int i = 0; i < nsps; i++) {
        if (c.n - o < 2) return 0; size_t l = rd16(c.p + o); o += 2;
        if (l < 2 || l > 256 || c.n - o < l || (c.p[o] & 0x1f) != 7) return 0; o += l;
    }
    if (c.n - o < 1) return 0; int npps = c.p[o++];
    if (npps < 1 || npps > 4) return 0;
    for (int i = 0; i < npps; i++) {
        if (c.n - o < 2) return 0; size_t l = rd16(c.p + o); o += 2;
        if (l < 1 || l > 256 || c.n - o < l || (c.p[o] & 0x1f) != 8) return 0; o += l;
    }
    return c.n - o <= 16;                                 // High-Profile-Anhang (Chroma, Bittiefe)
}
// MPEG-4-Deskriptorlänge (1–4 Bytes)
static int descLen(Span c, size_t *o, size_t *len) {
    size_t l = 0;
    for (int i = 0; i < 4; i++) {
        if (*o >= c.n) return 0;
        uint8_t b = c.p[(*o)++]; l = l << 7 | (b & 0x7f);
        if (!(b & 0x80)) { *len = l; return l <= c.n - *o; }
    }
    return 0;
}
static int checkEsds(Span c) {
    if (c.n < 4 || c.n > 256 || rd32(c.p) != 0) return 0;  // Version 0, keine Flags
    size_t o = 4, l;
    if (o >= c.n || c.p[o++] != 3 || !descLen(c, &o, &l)) return 0;     // ES_Descriptor
    if (c.n - o < 3) return 0;
    uint8_t flags = c.p[o + 2]; o += 3;
    if (flags & 0xE0) return 0;                            // keine Abhängigkeit, URL, OCR
    if (o >= c.n || c.p[o++] != 4 || !descLen(c, &o, &l)) return 0;     // DecoderConfigDescriptor
    if (l < 13 || c.n - o < 13 || c.p[o] != 0x40) return 0;              // AAC
    o += 13;
    if (o >= c.n || c.p[o++] != 5 || !descLen(c, &o, &l)) return 0;     // DecoderSpecificInfo
    return l >= 2 && l <= 16;
}

// ---- eine Spur einlesen und prüfen ----
// Drehmatrix: a, b, c, d nur 0 / +1 / -1 (16.16), u = v = 0, w = 1 (2.30), Verschiebung begrenzt
static int readMatrix(Span tkhd, uint32_t m[9]) {
    size_t at = tkhd.n >= 4 && tkhd.p[0] == 1 ? 52 : 40;
    if (tkhd.n < at + 36) return 0;
    for (int i = 0; i < 9; i++) m[i] = rd32(tkhd.p + at + i * 4);
    const int ab[4] = { 0, 1, 3, 4 };
    for (int i = 0; i < 4; i++) { uint32_t v = m[ab[i]]; if (v != 0 && v != 0x00010000 && v != 0xFFFF0000) return 0; }
    if (m[2] != 0 || m[5] != 0 || m[8] != 0x40000000) return 0;
    int32_t tx = (int32_t)m[6], ty = (int32_t)m[7];
    if (tx < -(4096 << 16) || tx > (4096 << 16) || ty < -(4096 << 16) || ty > (4096 << 16)) return 0;
    return 1;
}

static int readTrack(Span trak, Track *t, size_t fileLen) {
    Span mdia, mdhd, hdlr, minf, stbl, stsd, stts, stsc, stsz, co, ctts, stss, tkhd;
    if (!needBox(trak, FOURCC('m','d','i','a'), &mdia) || !needBox(mdia, FOURCC('m','d','h','d'), &mdhd) ||
        !needBox(mdia, FOURCC('h','d','l','r'), &hdlr) || !needBox(mdia, FOURCC('m','i','n','f'), &minf) ||
        !needBox(minf, FOURCC('s','t','b','l'), &stbl)) return 0;
    if (hdlr.n < 12) return 0;
    t->handler = rd32(hdlr.p + 8);
    if (t->handler != FOURCC('v','i','d','e') && t->handler != FOURCC('s','o','u','n')) return -1;   // andere Spuren: weglassen
    if (mdhd.n < 24) return 0;
    if (mdhd.p[0] == 1) { if (mdhd.n < 36) return 0; t->timescale = rd32(mdhd.p + 20); t->duration = rd64(mdhd.p + 24); }
    else { t->timescale = rd32(mdhd.p + 12); t->duration = rd32(mdhd.p + 16); }
    if (t->timescale == 0 || t->timescale > 1000000 || t->duration / t->timescale > kMaxSeconds) return 0;

    // Beschreibung: genau ein Eintrag, avc1 bzw. mp4a, nur dessen Konfigurations-Box wird übernommen
    if (!needBox(stbl, FOURCC('s','t','s','d'), &stsd) || stsd.n < 16 || rd32(stsd.p + 4) != 1) return 0;
    Span entry = { stsd.p + 8, stsd.n - 8 };
    uint32_t esz = rd32(entry.p), etype = rd32(entry.p + 4);
    if (esz < 8 || esz > entry.n) return 0;
    entry.n = esz;
    if (t->handler == FOURCC('v','i','d','e')) {
        if (etype != FOURCC('a','v','c','1') || esz < 86) return 0;
        t->width = rd16(entry.p + 32); t->height = rd16(entry.p + 34);
        if (!t->width || !t->height || t->width > kMaxSide || t->height > kMaxSide) return 0;
        Span kids = { entry.p + 86, esz - 86 };
        if (!needBox(kids, FOURCC('a','v','c','C'), &t->config) || !checkAvcC(t->config)) return 0;
        if (needBox(trak, FOURCC('t','k','h','d'), &tkhd) && readMatrix(tkhd, t->matrix)) t->hasMatrix = 1;
    } else {
        if (etype != FOURCC('m','p','4','a') || esz < 36) return 0;
        if (rd16(entry.p + 16) != 0) return 0;              // nur Version 0 der Audio-Beschreibung
        t->channels = rd16(entry.p + 24); t->rate = rd32(entry.p + 32) >> 16;
        if (t->channels < 1 || t->channels > 2 || t->rate < 8000 || t->rate > 48000) return 0;
        Span kids = { entry.p + 36, esz - 36 };
        if (!needBox(kids, FOURCC('e','s','d','s'), &t->config) || !checkEsds(t->config)) return 0;
    }

    // Größen
    if (!needBox(stbl, FOURCC('s','t','s','z'), &stsz) || stsz.n < 12) return 0;
    uint32_t uni = rd32(stsz.p + 4), n = rd32(stsz.p + 8);
    if (n == 0 || n > kMaxSamples) return 0;
    if (!uni && stsz.n < 12 + (size_t)n * 4) return 0;
    t->nSamples = n; t->sizes = calloc(n, 4); t->offsets = calloc(n, 8);
    if (!t->sizes || !t->offsets) return 0;
    for (uint32_t i = 0; i < n; i++) { t->sizes[i] = uni ? uni : rd32(stsz.p + 12 + (size_t)i * 4); if (!t->sizes[i] || t->sizes[i] > 4 * 1024 * 1024) return 0; }

    // Chunk-Positionen
    int is64 = 0;
    if (!needBox(stbl, FOURCC('s','t','c','o'), &co)) { if (!needBox(stbl, FOURCC('c','o','6','4'), &co)) return 0; is64 = 1; }
    if (co.n < 8) return 0;
    uint32_t nChunks = rd32(co.p + 4);
    if (!nChunks || nChunks > kMaxSamples || co.n < 8 + (size_t)nChunks * (is64 ? 8 : 4)) return 0;

    // Samples je Chunk -> Position jedes Samples
    if (!needBox(stbl, FOURCC('s','t','s','c'), &stsc) || stsc.n < 8) return 0;
    uint32_t nStsc = rd32(stsc.p + 4);
    if (!nStsc || nStsc > nChunks || stsc.n < 8 + (size_t)nStsc * 12) return 0;
    uint32_t s = 0;
    for (uint32_t e = 0; e < nStsc; e++) {
        uint32_t first = rd32(stsc.p + 8 + e * 12), per = rd32(stsc.p + 12 + e * 12), desc = rd32(stsc.p + 16 + e * 12);
        uint32_t next = e + 1 < nStsc ? rd32(stsc.p + 8 + (e + 1) * 12) : nChunks + 1;
        if (first < 1 || next <= first || next > nChunks + 1 || desc != 1 || !per || per > kMaxSamples) return 0;
        for (uint32_t c = first; c < next; c++) {
            uint64_t off = is64 ? rd64(co.p + 8 + (size_t)(c - 1) * 8) : rd32(co.p + 8 + (size_t)(c - 1) * 4);
            for (uint32_t k = 0; k < per; k++) {
                if (s >= n) return 0;
                if (off > fileLen || t->sizes[s] > fileLen - off) return 0;    // Sample muss in der Datei liegen
                t->offsets[s] = off; off += t->sizes[s]; s++;
            }
        }
    }
    if (s != n) return 0;

    // Zeiten
    if (!needBox(stbl, FOURCC('s','t','t','s'), &stts) || stts.n < 8) return 0;
    t->nStts = rd32(stts.p + 4);
    if (!t->nStts || t->nStts > n || stts.n < 8 + (size_t)t->nStts * 8) return 0;
    t->sttsCount = calloc(t->nStts, 4); t->sttsDelta = calloc(t->nStts, 4);
    if (!t->sttsCount || !t->sttsDelta) return 0;
    uint64_t total = 0;
    for (uint32_t i = 0; i < t->nStts; i++) {
        t->sttsCount[i] = rd32(stts.p + 8 + i * 8); t->sttsDelta[i] = rd32(stts.p + 12 + i * 8);
        total += t->sttsCount[i];
    }
    if (total != n) return 0;
    int okc = 1;
    if (findBox(stbl, FOURCC('c','t','t','s'), &ctts, &okc)) {
        if (ctts.n < 8 || (ctts.p[0] != 0 && ctts.p[0] != 1)) return 0;
        t->cttsVer = ctts.p[0];   // Version 1: Verschiebungen mit Vorzeichen
        t->nCtts = rd32(ctts.p + 4);
        if (!t->nCtts || t->nCtts > n || ctts.n < 8 + (size_t)t->nCtts * 8) return 0;
        t->cttsCount = calloc(t->nCtts, 4); t->cttsOff = calloc(t->nCtts, 4);
        if (!t->cttsCount || !t->cttsOff) return 0;
        uint64_t sum = 0;
        for (uint32_t i = 0; i < t->nCtts; i++) { t->cttsCount[i] = rd32(ctts.p + 8 + i * 8); t->cttsOff[i] = rd32(ctts.p + 12 + i * 8); sum += t->cttsCount[i]; }
        if (sum != n) return 0;
    } else if (!okc) return 0;
    int oks = 1;
    if (t->handler == FOURCC('v','i','d','e') && findBox(stbl, FOURCC('s','t','s','s'), &stss, &oks)) {
        if (stss.n < 8) return 0;
        t->nStss = rd32(stss.p + 4);
        if (t->nStss > n || stss.n < 8 + (size_t)t->nStss * 4) return 0;
        t->stss = calloc(t->nStss ? t->nStss : 1, 4);
        if (!t->stss) return 0;
        for (uint32_t i = 0; i < t->nStss; i++) { t->stss[i] = rd32(stss.p + 8 + i * 4); if (!t->stss[i] || t->stss[i] > n) return 0; }
    } else if (!oks) return 0;
    return 1;
}

// H.264-Bilder: Folge aus [4 Byte Länge][NAL], NAL-Typ 1–12, Längen müssen genau aufgehen
static int checkNALs(const uint8_t *p, uint32_t len) {
    uint32_t o = 0;
    while (o < len) {
        if (len - o < 5) return 0;
        uint32_t l = rd32(p + o); o += 4;
        if (!l || l > len - o) return 0;
        uint8_t type = p[o] & 0x1f;
        if ((p[o] & 0x80) || type < 1 || type > 12) return 0;
        o += l;
    }
    return 1;
}

// ---- Ausgabe ----
static void put32(NSMutableData *d, uint32_t v) { uint8_t b[4] = { v >> 24, v >> 16, v >> 8, v }; [d appendBytes:b length:4]; }
static void put16(NSMutableData *d, uint16_t v) { uint8_t b[2] = { v >> 8, v }; [d appendBytes:b length:2]; }
static void putZero(NSMutableData *d, size_t n) { [d increaseLengthBy:n]; }
static NSUInteger openBox(NSMutableData *d, uint32_t type) { NSUInteger at = d.length; put32(d, 0); put32(d, type); return at; }
static void closeBox(NSMutableData *d, NSUInteger at) {
    uint32_t sz = (uint32_t)(d.length - at); uint8_t b[4] = { sz >> 24, sz >> 16, sz >> 8, sz };
    [d replaceBytesInRange:NSMakeRange(at, 4) withBytes:b];
}
static void putMatrixOf(NSMutableData *d, const Track *t) {
    if (!t || !t->hasMatrix) { put32(d, 0x00010000); put32(d, 0); put32(d, 0); put32(d, 0); put32(d, 0x00010000); put32(d, 0); put32(d, 0); put32(d, 0); put32(d, 0x40000000); return; }
    for (int i = 0; i < 9; i++) put32(d, t->matrix[i]);
}
static void putMatrix(NSMutableData *d) {
    put32(d, 0x00010000); put32(d, 0); put32(d, 0); put32(d, 0); put32(d, 0x00010000); put32(d, 0);
    put32(d, 0); put32(d, 0); put32(d, 0x40000000);
}

static void writeTrack(NSMutableData *m, Track *t, uint32_t trackId, uint32_t movieDuration, const uint64_t *newOffsets) {
    BOOL video = t->handler == FOURCC('v','i','d','e');
    NSUInteger trak = openBox(m, FOURCC('t','r','a','k'));
    NSUInteger tkhd = openBox(m, FOURCC('t','k','h','d'));
    put32(m, 0x00000003); put32(m, 0); put32(m, 0); put32(m, trackId); put32(m, 0); put32(m, movieDuration);
    putZero(m, 8); put16(m, 0); put16(m, video ? 0 : 1); put16(m, video ? 0 : 0x0100); put16(m, 0);
    putMatrixOf(m, video ? t : NULL); put32(m, video ? (uint32_t)t->width << 16 : 0); put32(m, video ? (uint32_t)t->height << 16 : 0);
    closeBox(m, tkhd);
    NSUInteger mdia = openBox(m, FOURCC('m','d','i','a'));
    NSUInteger mdhd = openBox(m, FOURCC('m','d','h','d'));
    put32(m, 0); put32(m, 0); put32(m, 0); put32(m, t->timescale); put32(m, (uint32_t)MIN(t->duration, 0xFFFFFFFFull)); put16(m, 0x55C4); put16(m, 0);
    closeBox(m, mdhd);
    NSUInteger hdlr = openBox(m, FOURCC('h','d','l','r'));
    put32(m, 0); put32(m, 0); put32(m, t->handler); putZero(m, 12); [m appendBytes:"\0" length:1];
    closeBox(m, hdlr);
    NSUInteger minf = openBox(m, FOURCC('m','i','n','f'));
    if (video) { NSUInteger v = openBox(m, FOURCC('v','m','h','d')); put32(m, 1); putZero(m, 8); closeBox(m, v); }
    else { NSUInteger s = openBox(m, FOURCC('s','m','h','d')); put32(m, 0); put32(m, 0); closeBox(m, s); }
    NSUInteger dinf = openBox(m, FOURCC('d','i','n','f'));
    NSUInteger dref = openBox(m, FOURCC('d','r','e','f')); put32(m, 0); put32(m, 1);
    NSUInteger url = openBox(m, FOURCC('u','r','l',' ')); put32(m, 1); closeBox(m, url);
    closeBox(m, dref); closeBox(m, dinf);
    NSUInteger stbl = openBox(m, FOURCC('s','t','b','l'));
    NSUInteger stsd = openBox(m, FOURCC('s','t','s','d')); put32(m, 0); put32(m, 1);
    if (video) {
        NSUInteger e = openBox(m, FOURCC('a','v','c','1'));
        putZero(m, 6); put16(m, 1); putZero(m, 16); put16(m, t->width); put16(m, t->height);
        put32(m, 0x00480000); put32(m, 0x00480000); put32(m, 0); put16(m, 1); putZero(m, 32); put16(m, 0x0018); put16(m, 0xFFFF);
        NSUInteger c = openBox(m, FOURCC('a','v','c','C')); [m appendBytes:t->config.p length:t->config.n]; closeBox(m, c);
        closeBox(m, e);
    } else {
        NSUInteger e = openBox(m, FOURCC('m','p','4','a'));
        putZero(m, 6); put16(m, 1); putZero(m, 8); put16(m, t->channels); put16(m, 16); put16(m, 0); put16(m, 0); put32(m, t->rate << 16);
        NSUInteger c = openBox(m, FOURCC('e','s','d','s')); [m appendBytes:t->config.p length:t->config.n]; closeBox(m, c);
        closeBox(m, e);
    }
    closeBox(m, stsd);
    NSUInteger stts = openBox(m, FOURCC('s','t','t','s')); put32(m, 0); put32(m, t->nStts);
    for (uint32_t i = 0; i < t->nStts; i++) { put32(m, t->sttsCount[i]); put32(m, t->sttsDelta[i]); }
    closeBox(m, stts);
    if (t->nCtts) {
        NSUInteger ctts = openBox(m, FOURCC('c','t','t','s')); put32(m, (uint32_t)t->cttsVer << 24); put32(m, t->nCtts);
        for (uint32_t i = 0; i < t->nCtts; i++) { put32(m, t->cttsCount[i]); put32(m, t->cttsOff[i]); }
        closeBox(m, ctts);
    }
    if (t->stss) {
        NSUInteger stss = openBox(m, FOURCC('s','t','s','s')); put32(m, 0); put32(m, t->nStss);
        for (uint32_t i = 0; i < t->nStss; i++) put32(m, t->stss[i]);
        closeBox(m, stss);
    }
    NSUInteger stsc = openBox(m, FOURCC('s','t','s','c')); put32(m, 0); put32(m, 1); put32(m, 1); put32(m, 1); put32(m, 1); closeBox(m, stsc);
    NSUInteger stsz = openBox(m, FOURCC('s','t','s','z')); put32(m, 0); put32(m, 0); put32(m, t->nSamples);
    for (uint32_t i = 0; i < t->nSamples; i++) put32(m, t->sizes[i]);
    closeBox(m, stsz);
    NSUInteger stco = openBox(m, FOURCC('s','t','c','o')); put32(m, 0); put32(m, t->nSamples);
    for (uint32_t i = 0; i < t->nSamples; i++) put32(m, (uint32_t)newOffsets[i]);
    closeBox(m, stco);
    closeBox(m, stbl); closeBox(m, minf); closeBox(m, mdia); closeBox(m, trak);
}

static NSData *buildFile(NSData *src, Track *tracks, int nTracks) {
    // Dauer des Films in Millisekunden
    uint32_t movieMs = 0;
    for (int i = 0; i < nTracks; i++) { uint64_t ms = tracks[i].duration * 1000 / tracks[i].timescale; if (ms > movieMs) movieMs = (uint32_t)ms; }
    uint64_t payload = 0;
    for (int i = 0; i < nTracks; i++) for (uint32_t s = 0; s < tracks[i].nSamples; s++) payload += tracks[i].sizes[s];
    if (payload > kMaxInput) return nil;
    uint64_t *newOff[2] = { calloc(tracks[0].nSamples, 8), nTracks > 1 ? calloc(tracks[1].nSamples, 8) : NULL };
    if (!newOff[0] || (nTracks > 1 && !newOff[1])) { free(newOff[0]); free(newOff[1]); return nil; }
    NSMutableData *out = nil;
    // zweimal: erst Größe von moov bestimmen (Offsets zeigen hinter moov in mdat), dann schreiben
    for (int pass = 0; pass < 2; pass++) {
        NSMutableData *head = [NSMutableData data];
        NSUInteger ftyp = openBox(head, FOURCC('f','t','y','p'));
        put32(head, FOURCC('i','s','o','m')); put32(head, 0x200);
        put32(head, FOURCC('i','s','o','m')); put32(head, FOURCC('i','s','o','2')); put32(head, FOURCC('a','v','c','1')); put32(head, FOURCC('m','p','4','1'));
        closeBox(head, ftyp);
        NSUInteger moov = openBox(head, FOURCC('m','o','o','v'));
        NSUInteger mvhd = openBox(head, FOURCC('m','v','h','d'));
        put32(head, 0); put32(head, 0); put32(head, 0); put32(head, 1000); put32(head, movieMs); put32(head, 0x00010000); put16(head, 0x0100);
        putZero(head, 10); putMatrix(head); putZero(head, 24); put32(head, (uint32_t)nTracks + 1);
        closeBox(head, mvhd);
        for (int i = 0; i < nTracks; i++) writeTrack(head, &tracks[i], (uint32_t)i + 1, movieMs, newOff[i]);
        closeBox(head, moov);
        uint64_t pos = head.length + 8;                    // hinter dem mdat-Kopf
        for (int i = 0; i < nTracks; i++) for (uint32_t s = 0; s < tracks[i].nSamples; s++) { newOff[i][s] = pos; pos += tracks[i].sizes[s]; }
        if (pos > 0xFFFFFFFFull) break;
        if (pass == 1) {
            out = [NSMutableData dataWithCapacity:(NSUInteger)pos];   // Größe steht fest: kein Umkopieren beim Wachsen
            [out appendData:head];
            NSUInteger mdat = openBox(out, FOURCC('m','d','a','t'));
            const uint8_t *p = src.bytes;
            for (int i = 0; i < nTracks; i++) for (uint32_t s = 0; s < tracks[i].nSamples; s++) [out appendBytes:p + tracks[i].offsets[s] length:tracks[i].sizes[s]];
            closeBox(out, mdat);
        }
    }
    free(newOff[0]); free(newOff[1]);
    return out;
}

NSData *MeshMP4Sanitize(NSData *mp4, NSString **reason) {
    #define FAIL(msg) do { if (reason) *reason = @(msg); for (int k = 0; k < 2; k++) freeTrack(&tr[k]); return nil; } while (0)
    Track tr[2]; memset(tr, 0, sizeof tr);
    if (mp4.length < 16 || mp4.length > kMaxInput) FAIL("size");
    Span file = { mp4.bytes, mp4.length }, ftyp, moov;
    if (rd32(file.p + 4) != FOURCC('f','t','y','p') || !needBox(file, FOURCC('f','t','y','p'), &ftyp)) FAIL("ftyp");
    if (!needBox(file, FOURCC('m','o','o','v'), &moov)) FAIL("moov");
    // alle Spuren durchgehen: höchstens eine Bild- und eine Tonspur übernehmen
    int nTracks = 0, haveVideo = 0, haveAudio = 0;
    size_t o = 0;
    while (o < moov.n) {
        if (moov.n - o < 8) FAIL("moov box");
        uint64_t sz = rd32(moov.p + o); uint32_t t = rd32(moov.p + o + 4); size_t h = 8;
        if (sz == 1) { if (moov.n - o < 16) FAIL("moov box"); sz = rd64(moov.p + o + 8); h = 16; }
        if (sz < h || sz > moov.n - o) FAIL("moov box");
        if (t == FOURCC('t','r','a','k')) {
            Track tmp; memset(&tmp, 0, sizeof tmp);
            Span trak = { moov.p + o + h, (size_t)sz - h };
            int r = readTrack(trak, &tmp, mp4.length);
            if (r == 0) { freeTrack(&tmp); FAIL("track"); }
            BOOL v = tmp.handler == FOURCC('v','i','d','e');
            if (r == 1 && ((v && !haveVideo) || (!v && !haveAudio)) && nTracks < 2) {
                tr[nTracks++] = tmp; if (v) haveVideo = 1; else haveAudio = 1;
            } else freeTrack(&tmp);                         // Metadaten-, Zusatz- oder doppelte Spuren fallen weg
        }
        o += (size_t)sz;
    }
    if (!haveVideo) FAIL("no video");
    // jedes Bild: NAL-Rahmen müssen genau aufgehen
    const uint8_t *p = mp4.bytes;
    for (int i = 0; i < nTracks; i++) if (tr[i].handler == FOURCC('v','i','d','e'))
        for (uint32_t s = 0; s < tr[i].nSamples; s++) if (!checkNALs(p + tr[i].offsets[s], tr[i].sizes[s])) FAIL("nal");
    NSData *out = buildFile(mp4, tr, nTracks);
    if (!out) FAIL("build");
    for (int k = 0; k < 2; k++) freeTrack(&tr[k]);
    if (reason) *reason = nil;
    return out;
    #undef FAIL
}
