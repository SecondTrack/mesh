// scrypt (RFC 7914): Schlüsselableitung, die viel Speicher braucht und sich dadurch auf
// Grafikkarten schlecht parallelisieren lässt. Für Passphrasen statt PBKDF2.
// N × r × 128 Byte Speicher (N = 16384, r = 8: 16 MB). Gibt einen löschbaren Puffer zurück.
#import <Foundation/Foundation.h>

NSData *MeshScrypt(NSData *password, NSData *salt, uint32_t N, uint32_t r, uint32_t p, size_t length);
