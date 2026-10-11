#import "MeshCurve25519.h"
#import <CommonCrypto/CommonDigest.h>
#import "MeshMemory.h"

// Feldelemente mod 2^255 - 19 als 16 Glieder à 16 Bit (TweetNaCl).
typedef int64_t gf[16];

static const gf gf0 = {0}, gf1 = {1}, k121665 = {0xDB41, 1};
static const gf D  = {0x78a3, 0x1359, 0x4dca, 0x75eb, 0xd8ab, 0x4141, 0x0a4d, 0x0070,
                      0xe898, 0x7779, 0x4079, 0x8cc7, 0xfe73, 0x2b6f, 0x6cee, 0x5203};
static const gf D2 = {0xf159, 0x26b2, 0x9b94, 0xebd6, 0xb156, 0x8283, 0x149a, 0x00e0,
                      0xd130, 0xeef3, 0x80f2, 0x198e, 0xfce7, 0x56df, 0xd9dc, 0x2406};
static const gf BX = {0xd51a, 0x8f25, 0x2d60, 0xc956, 0xa7b2, 0x9525, 0xc760, 0x692c,
                      0xdc5c, 0xfdd6, 0xe231, 0xc0a4, 0x53fe, 0xcd6e, 0x36d3, 0x2169};
static const gf BY = {0x6658, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666,
                      0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666};
static const gf SQRTM1 = {0xa0b0, 0x4a0e, 0x1b27, 0xc4ee, 0xe478, 0xad2f, 0x1806, 0x2f43,
                          0xd7a7, 0x3dfb, 0x0099, 0x2b4d, 0xdf0b, 0x4fc1, 0x2480, 0x2b83};
// Gruppenordnung L = 2^252 + 27742317777372353535851937790883648493, little endian
static const int64_t L[32] = {0xed, 0xd3, 0xf5, 0x5c, 0x1a, 0x63, 0x12, 0x58, 0xd6, 0x9c, 0xf7, 0xa2,
                              0xde, 0xf9, 0xde, 0x14, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x10};

static void set25519(gf r, const gf a) { for (int i = 0; i < 16; i++) r[i] = a[i]; }

static void car25519(gf o) {
    for (int i = 0; i < 16; i++) {
        o[i] += (1LL << 16);
        int64_t c = o[i] >> 16;
        o[(i + 1) * (i < 15)] += c - 1 + 37 * (c - 1) * (i == 15);
        o[i] -= c * 65536;
    }
}

static void sel25519(gf p, gf q, int b) {
    int64_t c = ~(b - 1);
    for (int i = 0; i < 16; i++) { int64_t t = c & (p[i] ^ q[i]); p[i] ^= t; q[i] ^= t; }
}

static void pack25519(uint8_t o[32], const gf n) {
    gf m, t;
    set25519(t, n);
    car25519(t); car25519(t); car25519(t);
    for (int j = 0; j < 2; j++) {
        m[0] = t[0] - 0xffed;
        for (int i = 1; i < 15; i++) {
            m[i] = t[i] - 0xffff - ((m[i - 1] >> 16) & 1);
            m[i - 1] &= 0xffff;
        }
        m[15] = t[15] - 0x7fff - ((m[14] >> 16) & 1);
        int b = (int)((m[15] >> 16) & 1);
        m[14] &= 0xffff;
        sel25519(t, m, 1 - b);
    }
    for (int i = 0; i < 16; i++) { o[2 * i] = t[i] & 0xff; o[2 * i + 1] = (uint8_t)(t[i] >> 8); }
}

static int verify32(const uint8_t *x, const uint8_t *y) {
    unsigned d = 0;
    for (int i = 0; i < 32; i++) d |= x[i] ^ y[i];
    return (1 & ((d - 1) >> 8)) - 1;   // 0 gleich, -1 verschieden
}

static int neq25519(const gf a, const gf b) {
    uint8_t c[32], d[32];
    pack25519(c, a); pack25519(d, b);
    return verify32(c, d);
}

static uint8_t par25519(const gf a) { uint8_t d[32]; pack25519(d, a); return d[0] & 1; }

static void unpack25519(gf o, const uint8_t n[32]) {
    for (int i = 0; i < 16; i++) o[i] = n[2 * i] + ((int64_t)n[2 * i + 1] << 8);
    o[15] &= 0x7fff;
}

static void A(gf o, const gf a, const gf b) { for (int i = 0; i < 16; i++) o[i] = a[i] + b[i]; }
static void Z(gf o, const gf a, const gf b) { for (int i = 0; i < 16; i++) o[i] = a[i] - b[i]; }

static void M(gf o, const gf a, const gf b) {
    int64_t t[31] = {0};
    for (int i = 0; i < 16; i++) for (int j = 0; j < 16; j++) t[i + j] += a[i] * b[j];
    for (int i = 0; i < 15; i++) t[i] += 38 * t[i + 16];
    for (int i = 0; i < 16; i++) o[i] = t[i];
    car25519(o); car25519(o);
}

static void S(gf o, const gf a) { M(o, a, a); }

static void inv25519(gf o, const gf in) {
    gf c;
    set25519(c, in);
    for (int a = 253; a >= 0; a--) { S(c, c); if (a != 2 && a != 4) M(c, c, in); }
    set25519(o, c);
}

static void pow2523(gf o, const gf in) {
    gf c;
    set25519(c, in);
    for (int a = 250; a >= 0; a--) { S(c, c); if (a != 1) M(c, c, in); }
    set25519(o, c);
}

#pragma mark - X25519

void MeshX25519(uint8_t out[32], const uint8_t scalar[32], const uint8_t point[32]) {
    uint8_t z[32];
    gf x, a, b, c, d, e, f;
    memcpy(z, scalar, 32);
    z[31] = (z[31] & 127) | 64;
    z[0] &= 248;
    unpack25519(x, point);
    set25519(b, x);
    set25519(a, gf0); set25519(c, gf0); set25519(d, gf0);
    a[0] = d[0] = 1;
    for (int i = 254; i >= 0; --i) {
        int r = (z[i >> 3] >> (i & 7)) & 1;
        sel25519(a, b, r); sel25519(c, d, r);
        A(e, a, c); Z(a, a, c); A(c, b, d); Z(b, b, d);
        S(d, e); S(f, a); M(a, c, a); M(c, b, e);
        A(e, a, c); Z(a, a, c); S(b, a); Z(c, d, f);
        M(a, c, k121665); A(a, a, d); M(c, c, a); M(a, d, f);
        M(d, b, x); S(b, e);
        sel25519(a, b, r); sel25519(c, d, r);
    }
    inv25519(c, c);
    M(a, a, c);
    pack25519(out, a);
    MeshWipeBytes(z, sizeof(z));
    MeshWipeBytes(a, sizeof(a)); MeshWipeBytes(b, sizeof(b)); MeshWipeBytes(c, sizeof(c));
    MeshWipeBytes(d, sizeof(d)); MeshWipeBytes(e, sizeof(e)); MeshWipeBytes(f, sizeof(f));
}

void MeshX25519Base(uint8_t pub[32], const uint8_t scalar[32]) {
    static const uint8_t nine[32] = {9};
    MeshX25519(pub, scalar, nine);
}

#pragma mark - Edwards-Punkte

typedef gf point[4];   // erweiterte Koordinaten X, Y, Z, T

static void add(point p, point q) {
    gf a, b, c, d, t, e, f, g, h;
    Z(a, p[1], p[0]); Z(t, q[1], q[0]); M(a, a, t);
    A(b, p[0], p[1]); A(t, q[0], q[1]); M(b, b, t);
    M(c, p[3], q[3]); M(c, c, D2);
    M(d, p[2], q[2]); A(d, d, d);
    Z(e, b, a); Z(f, d, c); A(g, d, c); A(h, b, a);
    M(p[0], e, f); M(p[1], h, g); M(p[2], g, f); M(p[3], e, h);
}

static void cswap(point p, point q, uint8_t b) { for (int i = 0; i < 4; i++) sel25519(p[i], q[i], b); }

static void pack(uint8_t r[32], point p) {
    gf tx, ty, zi;
    inv25519(zi, p[2]);
    M(tx, p[0], zi); M(ty, p[1], zi);
    pack25519(r, ty);
    r[31] ^= par25519(tx) << 7;
}

static void scalarmult(point p, point q, const uint8_t s[32]) {
    set25519(p[0], gf0); set25519(p[1], gf1); set25519(p[2], gf1); set25519(p[3], gf0);
    for (int i = 255; i >= 0; --i) {
        uint8_t b = (s[i / 8] >> (i & 7)) & 1;
        cswap(p, q, b);
        add(q, p);
        add(p, p);
        cswap(p, q, b);
    }
}

static void scalarbase(point p, const uint8_t s[32]) {
    point q;
    set25519(q[0], BX); set25519(q[1], BY); set25519(q[2], gf1); M(q[3], BX, BY);
    scalarmult(p, q, s);
}

// Punkt aus 32 Byte, negiert (für die Prüfung: S·B - h·A). -1 bei ungültigem Punkt.
static int unpackneg(point r, const uint8_t p[32]) {
    gf t, chk, num, den, den2, den4, den6;
    set25519(r[2], gf1);
    unpack25519(r[1], p);
    S(num, r[1]); M(den, num, D); Z(num, num, r[2]); A(den, r[2], den);
    S(den2, den); S(den4, den2); M(den6, den4, den2);
    M(t, den6, num); M(t, t, den);
    pow2523(t, t);
    M(t, t, num); M(t, t, den); M(t, t, den); M(r[0], t, den);
    S(chk, r[0]); M(chk, chk, den);
    if (neq25519(chk, num)) M(r[0], r[0], SQRTM1);
    S(chk, r[0]); M(chk, chk, den);
    if (neq25519(chk, num)) return -1;
    if (par25519(r[0]) == (p[31] >> 7)) Z(r[0], gf0, r[0]);
    M(r[3], r[0], r[1]);
    return 0;
}

#pragma mark - Skalare mod L

static void modL(uint8_t r[32], int64_t x[64]) {
    int64_t carry;
    int i, j;
    for (i = 63; i >= 32; --i) {
        carry = 0;
        for (j = i - 32; j < i - 12; ++j) {
            x[j] += carry - 16 * x[i] * L[j - (i - 32)];
            carry = (x[j] + 128) >> 8;
            x[j] -= carry * 256;
        }
        x[j] += carry;
        x[i] = 0;
    }
    carry = 0;
    for (j = 0; j < 32; j++) {
        x[j] += carry - (x[31] >> 4) * L[j];
        carry = x[j] >> 8;
        x[j] &= 255;
    }
    for (j = 0; j < 32; j++) x[j] -= carry * L[j];
    for (i = 0; i < 32; i++) {
        x[i + 1] += x[i] >> 8;
        r[i] = x[i] & 255;
    }
}

static void reduce64(uint8_t out[32], const uint8_t in[64]) {
    int64_t x[64];
    for (int i = 0; i < 64; i++) x[i] = in[i];
    modL(out, x);
    MeshWipeBytes(x, sizeof(x));
}

// out = a·b + c mod L
static void muladd(uint8_t out[32], const uint8_t a[32], const uint8_t b[32], const uint8_t c[32]) {
    int64_t x[64] = {0};
    for (int i = 0; i < 32; i++) x[i] = c[i];
    for (int i = 0; i < 32; i++) for (int j = 0; j < 32; j++) x[i + j] += (int64_t)a[i] * b[j];
    modL(out, x);
    MeshWipeBytes(x, sizeof(x));
}

static void sha512(uint8_t out[64], const uint8_t *a, size_t alen, const uint8_t *b, size_t blen,
                   const uint8_t *c, size_t clen, const uint8_t *d, size_t dlen) {
    CC_SHA512_CTX ctx;
    CC_SHA512_Init(&ctx);
    if (alen) CC_SHA512_Update(&ctx, a, (CC_LONG)alen);
    if (blen) CC_SHA512_Update(&ctx, b, (CC_LONG)blen);
    if (clen) CC_SHA512_Update(&ctx, c, (CC_LONG)clen);
    if (dlen) CC_SHA512_Update(&ctx, d, (CC_LONG)dlen);
    CC_SHA512_Final(out, &ctx);
}

#pragma mark - Signaturen

void MeshCurveSign(uint8_t sig[64], const uint8_t priv[32], const uint8_t *msg, size_t len, const uint8_t random[64]) {
    uint8_t k[32], edPub[32], nonce[64], r[32], hram[64], h[32];
    point p;
    memcpy(k, priv, 32);
    k[0] &= 248; k[31] = (k[31] & 127) | 64;   // wie X25519, sonst passt die Signatur nicht zum Schlüssel

    scalarbase(p, k);
    pack(edPub, p);
    uint8_t signBit = edPub[31] & 0x80;

    // Nonce wie curve_sigs: SHA-512(0xFE ‖ 0xFF×31 ‖ k ‖ msg ‖ random)
    uint8_t prefix[32];
    memset(prefix, 0xFF, 32); prefix[0] = 0xFE;
    sha512(nonce, prefix, 32, k, 32, msg, len, random, 64);
    reduce64(r, nonce);
    scalarbase(p, r);
    pack(sig, p);

    sha512(hram, sig, 32, edPub, 32, msg, len, NULL, 0);
    reduce64(h, hram);
    muladd(sig + 32, h, k, r);
    sig[63] = (sig[63] & 0x7F) | signBit;

    MeshWipeBytes(k, sizeof(k)); MeshWipeBytes(nonce, sizeof(nonce)); MeshWipeBytes(r, sizeof(r));
    MeshWipeBytes(p, sizeof(p));
}

BOOL MeshEd25519Verify(const uint8_t sig[64], const uint8_t edPub[32], const uint8_t *msg, size_t len) {
    point q, p;
    uint8_t hram[64], h[32], t[32];
    if (sig[63] & 224) return NO;   // S muss kleiner als 2^253 sein (wie ref10)
    if (unpackneg(q, edPub)) return NO;
    sha512(hram, sig, 32, edPub, 32, msg, len, NULL, 0);
    reduce64(h, hram);
    scalarmult(p, q, h);
    scalarbase(q, sig + 32);
    add(p, q);
    pack(t, p);
    return verify32(sig, t) == 0;
}

BOOL MeshCurveVerify(const uint8_t sig[64], const uint8_t pub[32], const uint8_t *msg, size_t len) {
    // Montgomery u -> Edwards y = (u - 1) / (u + 1); Vorzeichen aus dem obersten Bit der Signatur.
    gf u, num, den, y;
    uint8_t edPub[32], s[64];
    unpack25519(u, pub);
    Z(num, u, gf1);
    A(den, u, gf1);
    inv25519(den, den);
    M(y, num, den);
    pack25519(edPub, y);
    edPub[31] = (edPub[31] & 0x7F) | (sig[63] & 0x80);
    memcpy(s, sig, 64);
    s[63] &= 0x7F;
    return MeshEd25519Verify(s, edPub, msg, len);
}
