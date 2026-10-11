// 32 zufällige Bytes im Schlüsselbund, nur auf diesem Gerät gültig
// (kSecAttrAccessibleWhenUnlockedThisDeviceOnly). Fließen in die Schlüsselableitung des Vaults
// ein: Eine kopierte Datenbank (Backup, Dateizugriff) lässt sich dann nicht offline durchprobieren.
#import <Foundation/Foundation.h>

@interface MeshDeviceSecret : NSObject
// Alle drei liefern eine eigene Kopie, die der Aufrufer mit MeshWipe überschreibt.
+ (NSData *)existing;          // nil, wenn keins angelegt ist oder der Schlüsselbund nicht erreichbar ist
+ (NSData *)existingNotFound:(BOOL *)notFound;   // notFound = YES nur, wenn sicher keins existiert
+ (NSData *)existingOrCreate;
+ (void)remove;   // Geheimnis und Merker löschen

// Merker "Datenbank ist versiegelt", liegt im Schlüsselbund, damit ein Zurücksetzen der
// Versionsnummer in der Datenbankdatei nicht wieder Klartext zulässt.
+ (BOOL)databaseSealed;
+ (void)markDatabaseSealed;  // legt bei Bedarf an; nil, wenn der Schlüsselbund nicht nutzbar ist
@end
