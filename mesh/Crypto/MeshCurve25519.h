// Curve25519 für das Signal-Protokoll: X25519 (RFC 7748) und Signaturen wie libsignal
// (curve25519-java, curve_sigs: Ed25519 mit dem Montgomery-Schlüssel, Vorzeichenbit in der Signatur).
// Feldarithmetik nach TweetNaCl (konstante Laufzeit beim geheimen Schlüssel). Schlüssel sind
// 32 Byte roh; libsignal stellt öffentlichen Schlüsseln beim Serialisieren 0x05 voran.
#import <Foundation/Foundation.h>

void MeshX25519(uint8_t out[32], const uint8_t scalar[32], const uint8_t point[32]);
void MeshX25519Base(uint8_t pub[32], const uint8_t scalar[32]);   // öffentlicher Schlüssel

// Signatur über msg mit dem privaten Montgomery-Schlüssel; random: 64 Zufallsbytes.
// Signiert wird mit dem geclampten Schlüssel, damit sie zum öffentlichen passt.
void MeshCurveSign(uint8_t sig[64], const uint8_t priv[32], const uint8_t *msg, size_t len, const uint8_t random[64]);
BOOL MeshCurveVerify(const uint8_t sig[64], const uint8_t pub[32], const uint8_t *msg, size_t len);

// Standard-Ed25519-Prüfung (RFC 8032), nur für die Testvektoren.
BOOL MeshEd25519Verify(const uint8_t sig[64], const uint8_t edPub[32], const uint8_t *msg, size_t len);
