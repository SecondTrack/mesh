// Eine Zeile der Tabelle vault: der mit dem Entsperr-Code verschlüsselte Seckey (siehe MeshVault).
#import <Foundation/Foundation.h>

typedef NS_ENUM(int, MeshVaultKDF) {
    MeshVaultPBKDF2 = 0,   // 6-stellige PIN; iterations = Runden
    MeshVaultScrypt = 1    // Passphrase aus Wörtern; iterations = N (r = 8, p = 1)
};

@interface MeshVaultRecord : NSObject
@property (nonatomic, copy) NSData *salt;        // 16 Byte
@property (nonatomic, copy) NSData *iv;          // 16 Byte
@property (nonatomic, copy) NSData *ciphertext;  // AES-256-CBC über den Seckey
@property (nonatomic, copy) NSString *pubkey;    // x-only, hex: Prüfwert für den Code
@property (nonatomic) MeshVaultKDF kdf;
@property (nonatomic) int iterations;            // PBKDF2-Runden bzw. scrypt-N
@property (nonatomic) BOOL boundToDevice;        // Gerätegeheimnis steckt im Salt

- (BOOL)isEqualToRecord:(MeshVaultRecord *)other;
@end
