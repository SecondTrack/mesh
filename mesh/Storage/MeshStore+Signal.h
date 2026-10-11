// Signal-Zustand (Sitzungen, PreKeys, bekannte Identitäten) als versiegelte Schlüssel-Wert-Paare,
// dazu das Bundle jedes Kontakts. Ohne Datenschlüssel wird nichts gelesen oder geschrieben.
#import "MeshStore.h"
#import "MeshSignalStorage.h"

@interface MeshStore (Signal) <MeshSignalStorage>

- (NSString *)bundleForContact:(NSString *)pubkeyHex;
- (void)setBundle:(NSString *)bundle forContact:(NSString *)pubkeyHex;
@end
