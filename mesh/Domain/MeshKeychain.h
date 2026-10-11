// Einträge der App im Schlüsselbund (generic password, Dienst de.mesh.ios.vault). Alles nur auf
// diesem Gerät und nur bei entsperrtem Gerät lesbar (kSecAttrAccessibleWhenUnlockedThisDeviceOnly),
// nicht in Backups. Fehler werden protokolliert; errSecItemNotFound ist kein Fehler.
#import <Foundation/Foundation.h>
#import <Security/Security.h>

@interface MeshKeychain : NSObject
+ (NSData *)read:(NSString *)account status:(OSStatus *)status;   // nil, wenn nicht da oder Fehler
+ (OSStatus)add:(NSData *)data account:(NSString *)account;        // nur neu anlegen
+ (OSStatus)write:(NSData *)data account:(NSString *)account;      // ändern, sonst anlegen
// Ausnahme für Werte, die auch bei gesperrtem Gerät lesbar sein müssen (Notlöschungs-Token, nur ein
// Hash): ab dem ersten Entsperren nach dem Start, weiterhin nur auf diesem Gerät.
+ (OSStatus)writeReadableWhileLocked:(NSData *)data account:(NSString *)account;
+ (OSStatus)remove:(NSString *)account;                             // errSecItemNotFound gilt als Erfolg
@end
