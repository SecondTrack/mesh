// Zustand der PIN-Sperre im Schlüsselbund statt in den App-Einstellungen: Er übersteht so das
// Löschen der Einstellungsdatei und eine Neuinstallation der App.
#import "MeshPinGuard.h"

@interface MeshPinStore : NSObject <MeshPinStorage>
@end
