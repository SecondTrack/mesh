#import "MeshChaCha20.h"
#import "MeshMemory.h"

static inline uint32_t rotl(uint32_t x, int n) { return (x << n) | (x >> (32 - n)); }

static inline uint32_t load32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

#define QR(a, b, c, d) \
    a += b; d = rotl(d ^ a, 16); c += d; b = rotl(b ^ c, 12); \
    a += b; d = rotl(d ^ a, 8);  c += d; b = rotl(b ^ c, 7);

static void block(const uint32_t in[16], uint8_t out[64]) {
    uint32_t x[16];
    memcpy(x, in, sizeof(x));
    for (int i = 0; i < 10; i++) {
        QR(x[0], x[4], x[8],  x[12]) QR(x[1], x[5], x[9],  x[13])
        QR(x[2], x[6], x[10], x[14]) QR(x[3], x[7], x[11], x[15])
        QR(x[0], x[5], x[10], x[15]) QR(x[1], x[6], x[11], x[12])
        QR(x[2], x[7], x[8],  x[13]) QR(x[3], x[4], x[9],  x[14])
    }
    for (int i = 0; i < 16; i++) {
        uint32_t w = x[i] + in[i];
        out[4 * i] = (uint8_t)w; out[4 * i + 1] = (uint8_t)(w >> 8);
        out[4 * i + 2] = (uint8_t)(w >> 16); out[4 * i + 3] = (uint8_t)(w >> 24);
    }
    MeshWipeBytes(x, sizeof(x));
}

void MeshChaCha20(const uint8_t key[32], const uint8_t nonce[12], uint32_t counter,
                  const uint8_t *in, uint8_t *out, size_t length) {
    uint32_t state[16] = { 0x61707865, 0x3320646e, 0x79622d32, 0x6b206574 };
    for (int i = 0; i < 8; i++) state[4 + i] = load32(key + 4 * i);
    state[12] = counter;
    for (int i = 0; i < 3; i++) state[13 + i] = load32(nonce + 4 * i);
    uint8_t stream[64];
    for (size_t pos = 0; pos < length; pos += 64) {
        block(state, stream);
        size_t n = MIN((size_t)64, length - pos);
        for (size_t i = 0; i < n; i++) out[pos + i] = in[pos + i] ^ stream[i];
        state[12]++;
    }
    MeshWipeBytes(stream, sizeof(stream));
    MeshWipeBytes(state, sizeof(state));
}
