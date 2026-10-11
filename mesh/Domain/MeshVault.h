// Der geheime Schlüssel, mit dem Entsperr-Code verschlüsselt.
//
// Aufbau: KDF(Geheimnis, Salt ‖ Gerätegeheimnis) → AES-256-CBC über den 32-Byte-Seckey. KDF ist
// PBKDF2-HMAC-SHA256 für die 6-stellige PIN und scrypt (16 MB) für Passphrasen aus Wörtern.
// Das Gerätegeheimnis (MeshDeviceSecret) liegt im Schlüsselbund und nicht in der Datenbank;
// ohne es ist eine kopierte Datenbank nicht durchprobierbar. Ohne Gerätegeheimnis wird darum nichts
// gespeichert; Vaults aus der Zeit davor lassen sich noch öffnen und werden dabei gebunden.
// Der x-only-Pubkey dient als Prüfwert für den Code.
#import <Foundation/Foundation.h>

#import "MeshVaultRecord.h"
@class MeshKeys, MeshStore;

extern const int MeshVaultIterations;   // PBKDF2
extern const int MeshVaultScryptN;      // scrypt

typedef NS_ENUM(NSInteger, MeshVaultOpen) {
    MeshVaultOpened,
    MeshVaultWrongPin,
    MeshVaultSecretMissing    // mit Gerätegeheimnis verschlüsselt, das hier fehlt (anderes Gerät)
};

@interface MeshVault : NSObject
// deviceSecret nil = Schlüsselbund nicht verfügbar.
- (instancetype)initWithStore:(MeshStore *)store deviceSecret:(NSData *)deviceSecret;
// Nachträglich setzbar, wenn der Schlüsselbund erst später antwortet. Der Vault hält eine eigene
// Kopie; nil überschreibt sie (beim Sperren).
@property (nonatomic, copy) NSData *deviceSecret;

- (BOOL)exists;
@property (nonatomic, readonly) NSString *pubkey;   // aus dem Vault-Eintrag, auch gesperrt lesbar (öffentlich)
@property (nonatomic, readonly) MeshVaultKDF kdf;    // ebenso: PIN oder Passphrase (für den Sperrbildschirm)
@property (nonatomic, readonly) BOOL boundToDevice;   // vorhandener Vault nutzt das Gerätegeheimnis

// Erstes Festlegen des Codes: übernimmt den Klartext-Schlüssel alter Installationen oder erzeugt
// einen neuen. Der Klartext wird erst gelöscht, wenn der Vault sicher steht. nil bei Fehler.
- (MeshKeys *)createWithSecret:(NSString *)secret kdf:(MeshVaultKDF)kdf;

// Verschlüsselt und speichert, nur mit Gerätegeheimnis. YES nur, wenn der Datensatz geschrieben und unverändert
// zurückgelesen wurde, erst dann darf eine ältere Kopie des Schlüssels gelöscht werden.
- (BOOL)storeKeys:(MeshKeys *)keys secret:(NSString *)secret kdf:(MeshVaultKDF)kdf;
- (BOOL)storeKeys:(MeshKeys *)keys pin:(NSString *)pin;   // PBKDF2
// Für Änderungen über mehrere Vaults: vorher sichern, bei einem Fehler zurückschreiben.
- (MeshVaultRecord *)record;
- (BOOL)restoreRecord:(MeshVaultRecord *)record;

// YES, wenn openWithPin: rechnen kann: ein Vault ist da und, falls gebunden, das Gerätegeheimnis.
// Erst dann zählt ein Versuch.
- (BOOL)readyToOpen;
- (BOOL)recordReadable;   // NO: kein Vault oder die Datenbank antwortet nicht

// Öffnet den Vault. Ein alter Vault ohne Gerätegeheimnis wird dabei umgestellt.
- (MeshKeys *)openWithPin:(NSString *)pin result:(MeshVaultOpen *)result;
@end
