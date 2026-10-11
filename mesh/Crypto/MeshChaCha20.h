// ChaCha20 nach RFC 8439 (32-Byte-Schlüssel, 12-Byte-Nonce, Blockzähler ab `counter`).
// Ver- und Entschlüsseln sind dieselbe Operation. Für NIP-44; CommonCrypto auf iOS 6 kennt kein ChaCha.
#import <Foundation/Foundation.h>

void MeshChaCha20(const uint8_t key[32], const uint8_t nonce[12], uint32_t counter,
                  const uint8_t *in, uint8_t *out, size_t length);
