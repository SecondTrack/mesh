// Schlüsselmaterial in der Datenbank: der Vault und, nur noch zur Migration, der Klartext-Seckey
// alter Installationen (Tabelle identity). Nur für MeshVault (tests/layers_check.sh prüft das).
#import "MeshStore.h"
@class MeshVaultRecord;

@interface MeshStore (Vault)
- (BOOL)hasVault;
- (BOOL)saveVault:(MeshVaultRecord *)record;
- (MeshVaultRecord *)loadVault;          // nil = keiner

- (NSString *)loadIdentitySeckeyHex;    // nil = keine Klartext-Identität
- (BOOL)clearPlaintextIdentity;         // nach Migration in den Vault löschen
@end
