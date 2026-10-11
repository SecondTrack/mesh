#import "MeshVault.h"
#import "MeshStore+Vault.h"
#import "MeshVaultRecord.h"
#import "MeshKeys.h"
#import "MeshCrypto.h"
#import "MeshMemory.h"
#import "MeshHex.h"
#import "MeshScrypt.h"

const int MeshVaultIterations = 40000;
const int MeshVaultScryptN = 16384;

@implementation MeshVault {
    MeshStore *_store;
}

- (instancetype)initWithStore:(MeshStore *)store deviceSecret:(NSData *)deviceSecret {
    if ((self = [super init])) { _store = store; self.deviceSecret = deviceSecret; }
    return self;
}

- (void)setDeviceSecret:(NSData *)secret {
    MeshWipe(_deviceSecret);
    _deviceSecret = secret ? [secret mutableCopy] : nil;   // mit MeshWipe löschbar
}

- (void)dealloc { MeshWipe(_deviceSecret); }

- (BOOL)exists { return [_store hasVault]; }

- (BOOL)boundToDevice { return [_store loadVault].boundToDevice; }

- (NSString *)pubkey { return [_store loadVault].pubkey; }
- (MeshVaultKDF)kdf { return [_store loadVault].kdf; }

- (MeshVaultRecord *)record { return [_store loadVault]; }

- (BOOL)restoreRecord:(MeshVaultRecord *)record {
    return record && [_store saveVault:record] && [record isEqualToRecord:[_store loadVault]];
}

- (BOOL)recordReadable { return [_store loadVault] != nil; }

- (BOOL)readyToOpen {
    MeshVaultRecord *v = [_store loadVault];
    return v && (!v.boundToDevice || _deviceSecret.length == 32);
}

static NSData *deriveKey(NSString *pin, NSData *salt, NSData *secret, MeshVaultKDF kdf, int cost) {
    NSMutableData *s = [salt mutableCopy];
    if (secret) [s appendData:secret];
    NSData *key = nil;
    if (kdf == MeshVaultScrypt) {
        NSMutableData *pw = [[pin dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
        key = MeshScrypt(pw, s, (uint32_t)cost, 8, 1, 32);
        MeshWipe(pw);
    } else {
        key = [MeshCrypto pbkdf2:pin salt:s iters:cost];
    }
    MeshWipe(s);   // enthält das Gerätegeheimnis
    return key;
}

- (MeshKeys *)createWithSecret:(NSString *)secret kdf:(MeshVaultKDF)kdf {
    if ([self exists]) return nil;
    NSString *skHex = [_store loadIdentitySeckeyHex];
    MeshKeys *k = skHex.length == 64 ? [MeshKeys fromSeckey:[MeshHex decode:skHex]] : [MeshKeys generate];
    if (![self storeKeys:k secret:secret kdf:kdf]) return nil;
    if (skHex) [_store clearPlaintextIdentity];
    return k;
}

- (BOOL)storeKeys:(MeshKeys *)keys pin:(NSString *)pin { return [self storeKeys:keys secret:pin kdf:MeshVaultPBKDF2]; }

- (BOOL)storeKeys:(MeshKeys *)keys secret:(NSString *)pin kdf:(MeshVaultKDF)kdf {
    if (!keys || !pin.length || _deviceSecret.length != 32) return NO;
    int cost = kdf == MeshVaultScrypt ? MeshVaultScryptN : MeshVaultIterations;
    NSData *salt = [MeshCrypto randomBytes:16];
    NSData *iv   = [MeshCrypto randomBytes:16];
    NSData *dk   = deriveKey(pin, salt, _deviceSecret, kdf, cost);
    NSData *sk   = keys.seckey;   // nil, wenn der Schlüssel schon überschrieben ist
    NSData *ct   = sk.length == 32 ? [MeshCrypto aes256cbcEncrypt:sk key:dk iv:iv] : nil;
    MeshWipe(dk);
    MeshWipe(sk);
    if (salt.length != 16 || iv.length != 16 || ct.length != 48) return NO;

    MeshVaultRecord *r = [MeshVaultRecord new];
    r.salt = salt; r.iv = iv; r.ciphertext = ct;
    r.pubkey = [MeshHex encode:keys.xonlyPub];
    r.kdf = kdf;
    r.iterations = cost;
    r.boundToDevice = YES;
    return [_store saveVault:r] && [r isEqualToRecord:[_store loadVault]];
}

- (MeshKeys *)openWithPin:(NSString *)pin result:(MeshVaultOpen *)result {
    *result = MeshVaultWrongPin;
    MeshVaultRecord *v = [_store loadVault];
    if (!v || !pin.length || v.iterations <= 0) return nil;
    // Nur bekannte Verfahren und Kosten: eine manipulierte Datei soll weder 1 GB Speicher verlangen
    // noch die Ableitung auf ein paar Runden drücken oder ein unbekanntes Verfahren unterschieben.
    if (v.kdf == MeshVaultScrypt && v.iterations != MeshVaultScryptN) return nil;
    if (v.kdf == MeshVaultPBKDF2 && (v.iterations < 10000 || v.iterations > 1000000)) return nil;
    if (v.kdf != MeshVaultScrypt && v.kdf != MeshVaultPBKDF2) return nil;
    BOOL bound = v.boundToDevice;
    if (bound && !_deviceSecret) { *result = MeshVaultSecretMissing; return nil; }

    NSData *dk = deriveKey(pin, v.salt, bound ? _deviceSecret : nil, v.kdf, v.iterations);
    NSData *sk = [MeshCrypto aes256cbcDecrypt:v.ciphertext key:dk iv:v.iv];
    MeshKeys *k = (sk.length == 32) ? [MeshKeys fromSeckey:sk] : nil;
    MeshWipe(dk);
    MeshWipe(sk);
    // Bei falschem Code kann CBC zufällig gültiges Padding liefern: der Pubkey entscheidet.
    if (!k || ![[MeshHex encode:k.xonlyPub] isEqualToString:v.pubkey]) return nil;

    *result = MeshVaultOpened;
    if (!bound && _deviceSecret) [self storeKeys:k secret:pin kdf:v.kdf];   // alten Vault ans Gerät binden
    return k;
}

@end
