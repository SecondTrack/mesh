#import "MeshScrypt.h"
#import <CommonCrypto/CommonHMAC.h>
#import "MeshMemory.h"

// PBKDF2-HMAC-SHA256 mit einer Iteration, beliebig lang (mehr braucht scrypt nicht).
static void pbkdf2Once(NSData *password, const uint8_t *salt, size_t saltLen, uint8_t *out, size_t outLen) {
    uint8_t block[CC_SHA256_DIGEST_LENGTH];
    for (uint32_t i = 1; outLen > 0; i++) {
        uint8_t counter[4] = { i >> 24, i >> 16, i >> 8, i };
        CCHmacContext ctx;
        CCHmacInit(&ctx, kCCHmacAlgSHA256, password.bytes, password.length);
        CCHmacUpdate(&ctx, salt, saltLen);
        CCHmacUpdate(&ctx, counter, 4);
        CCHmacFinal(&ctx, block);
        size_t n = MIN(outLen, sizeof(block));
        memcpy(out, block, n);
        out += n; outLen -= n;
    }
    MeshWipeBytes(block, sizeof(block));
}

#define R(a, b) (((a) << (b)) | ((a) >> (32 - (b))))

static void salsa208(uint32_t b[16]) {
    uint32_t x[16];
    memcpy(x, b, sizeof(x));
    for (int i = 0; i < 8; i += 2) {
        x[ 4] ^= R(x[ 0] + x[12], 7);  x[ 8] ^= R(x[ 4] + x[ 0], 9);
        x[12] ^= R(x[ 8] + x[ 4], 13); x[ 0] ^= R(x[12] + x[ 8], 18);
        x[ 9] ^= R(x[ 5] + x[ 1], 7);  x[13] ^= R(x[ 9] + x[ 5], 9);
        x[ 1] ^= R(x[13] + x[ 9], 13); x[ 5] ^= R(x[ 1] + x[13], 18);
        x[14] ^= R(x[10] + x[ 6], 7);  x[ 2] ^= R(x[14] + x[10], 9);
        x[ 6] ^= R(x[ 2] + x[14], 13); x[10] ^= R(x[ 6] + x[ 2], 18);
        x[ 3] ^= R(x[15] + x[11], 7);  x[ 7] ^= R(x[ 3] + x[15], 9);
        x[11] ^= R(x[ 7] + x[ 3], 13); x[15] ^= R(x[11] + x[ 7], 18);
        x[ 1] ^= R(x[ 0] + x[ 3], 7);  x[ 2] ^= R(x[ 1] + x[ 0], 9);
        x[ 3] ^= R(x[ 2] + x[ 1], 13); x[ 0] ^= R(x[ 3] + x[ 2], 18);
        x[ 6] ^= R(x[ 5] + x[ 4], 7);  x[ 7] ^= R(x[ 6] + x[ 5], 9);
        x[ 4] ^= R(x[ 7] + x[ 6], 13); x[ 5] ^= R(x[ 4] + x[ 7], 18);
        x[11] ^= R(x[10] + x[ 9], 7);  x[ 8] ^= R(x[11] + x[10], 9);
        x[ 9] ^= R(x[ 8] + x[11], 13); x[10] ^= R(x[ 9] + x[ 8], 18);
        x[12] ^= R(x[15] + x[14], 7);  x[13] ^= R(x[12] + x[15], 9);
        x[14] ^= R(x[13] + x[12], 13); x[15] ^= R(x[14] + x[13], 18);
    }
    for (int i = 0; i < 16; i++) b[i] += x[i];
}

// BlockMix mit Salsa20/8: B (2r Blöcke à 64 Byte) -> Y, verschränkt (gerade, dann ungerade).
static void blockMix(const uint32_t *b, uint32_t *y, uint32_t r) {
    uint32_t x[16];
    memcpy(x, &b[(2 * r - 1) * 16], 64);
    for (uint32_t i = 0; i < 2 * r; i++) {
        for (int j = 0; j < 16; j++) x[j] ^= b[i * 16 + j];
        salsa208(x);
        memcpy(&y[(i / 2 + (i & 1) * r) * 16], x, 64);
    }
}

static void roMix(uint8_t *block, uint32_t N, uint32_t r, uint32_t *v, uint32_t *x, uint32_t *y) {
    size_t words = 32 * r;
    for (size_t k = 0; k < words; k++)   // little endian
        x[k] = (uint32_t)block[4 * k] | ((uint32_t)block[4 * k + 1] << 8) | ((uint32_t)block[4 * k + 2] << 16) | ((uint32_t)block[4 * k + 3] << 24);
    for (uint32_t i = 0; i < N; i += 2) {
        memcpy(&v[i * words], x, words * 4);
        blockMix(x, y, r);
        memcpy(&v[(i + 1) * words], y, words * 4);
        blockMix(y, x, r);
    }
    for (uint32_t i = 0; i < N; i += 2) {
        uint32_t j = x[(2 * r - 1) * 16] & (N - 1);
        for (size_t k = 0; k < words; k++) x[k] ^= v[j * words + k];
        blockMix(x, y, r);
        j = y[(2 * r - 1) * 16] & (N - 1);
        for (size_t k = 0; k < words; k++) y[k] ^= v[j * words + k];
        blockMix(y, x, r);
    }
    for (size_t k = 0; k < words; k++) {
        block[4 * k] = (uint8_t)x[k]; block[4 * k + 1] = (uint8_t)(x[k] >> 8);
        block[4 * k + 2] = (uint8_t)(x[k] >> 16); block[4 * k + 3] = (uint8_t)(x[k] >> 24);
    }
}

NSData *MeshScrypt(NSData *password, NSData *salt, uint32_t N, uint32_t r, uint32_t p, size_t length) {
    if (N < 2 || (N & (N - 1)) || !r || !p || !length || (uint64_t)r * p >= (1u << 30)) return nil;
    size_t blockLen = 128 * (size_t)r, vLen = blockLen * N;
    uint8_t *b = malloc(blockLen * p);
    uint32_t *v = malloc(vLen), *x = malloc(blockLen), *y = malloc(blockLen);
    NSMutableData *out = nil;
    if (b && v && x && y) {
        pbkdf2Once(password, salt.bytes, salt.length, b, blockLen * p);
        for (uint32_t i = 0; i < p; i++) roMix(b + i * blockLen, N, r, v, x, y);
        out = [NSMutableData dataWithLength:length];
        pbkdf2Once(password, b, blockLen * p, out.mutableBytes, length);
    }
    if (b) { MeshWipeBytes(b, blockLen * p); free(b); }
    if (v) { MeshWipeBytes(v, vLen); free(v); }
    if (x) { MeshWipeBytes(x, blockLen); free(x); }
    if (y) { MeshWipeBytes(y, blockLen); free(y); }
    return out;
}
