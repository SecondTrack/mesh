// Krypto-Primitiven über iOS-eigenes CommonCrypto (auf iOS 6 vorhanden):
// SHA-256 (Event-ID), AES-256-CBC (NIP-04-Payload), sichere Zufallsbytes.
// Kein mbedTLS/secp256k1 nötig: das sind reine Systemfunktionen.
// Die Rückgaben von hmacSHA256:, pbkdf2: und aes256cbc…: sind veränderbare Puffer, die sich mit
// MeshWipe (Support/MeshMemory.h) überschreiben lassen.
#import <Foundation/Foundation.h>

@interface MeshCrypto : NSObject

+ (NSData *)sha256:(NSData *)data;
+ (NSData *)sha512:(NSData *)data;

// HMAC-SHA256.
+ (NSData *)hmacSHA256:(NSData *)data key:(NSData *)key;

// HKDF-SHA256 (RFC 5869). Extract liefert den PRK, Expand bis 255·32 Byte (löschbare Puffer).
+ (NSData *)hkdfExtractSalt:(NSData *)salt ikm:(NSData *)ikm;
+ (NSData *)hkdfExpand:(NSData *)prk info:(NSData *)info length:(NSUInteger)length;

// Vergleich in konstanter Zeit (MACs); verschiedene Längen sind ungleich.
+ (BOOL)constantTimeEqual:(NSData *)a to:(NSData *)b;

// SHA-1, nur für den WebSocket-Handshake (RFC 6455), nicht für Sicherheitszwecke.
+ (NSData *)sha1:(NSData *)data;

// n kryptografisch sichere Zufallsbytes (SecRandomCopyBytes).
+ (NSData *)randomBytes:(NSUInteger)n;

// AES-256-CBC (PKCS7). key = 32 Byte, iv = 16 Byte. nil bei Fehler.
+ (NSData *)aes256cbcEncrypt:(NSData *)plain key:(NSData *)key iv:(NSData *)iv;
+ (NSData *)aes256cbcDecrypt:(NSData *)cipher key:(NSData *)key iv:(NSData *)iv;

// PBKDF2-HMAC-SHA256: leitet einen 32-Byte-Schlüssel aus PIN/Passwort ab (für die Seckey-Verschlüsselung).
+ (NSData *)pbkdf2:(NSString *)pin salt:(NSData *)salt iters:(int)iters;

@end

// Plattformunabhängige PBKDF2-Umsetzung (nur für iOS 4 und Tests direkt aufrufen).
NSData *MeshPBKDF2SHA256Portable(NSData *password, NSData *salt, int iterations);
