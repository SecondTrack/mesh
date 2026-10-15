// Texte für die Datenbank verschlüsseln (AES-256-CBC, dann HMAC-SHA256 darüber).
//
// Format: "enc2:" + Base64(IV 16 ‖ Chiffrat ‖ MAC 32). Der MAC deckt zusätzlich einen Kontext ab
// (Tabelle, Spalte, Zeile …): Ein Wert lässt sich so nicht unbemerkt in ein anderes Feld oder eine
// andere Zeile verschieben. Schlüssel für Verschlüsselung und MAC werden per HMAC aus dem
// 32-Byte-Datenschlüssel abgeleitet. "enc1:" ist das ältere Format ohne Kontext (nur Migration).
#import <Foundation/Foundation.h>

// Beide Teilschlüssel eines Datenschlüssels, einmal abgeleitet statt bei jedem Öffnen/Versiegeln
// zwei HMACs. Nur im RAM; wipe überschreibt sie (beim Sperren und bei jedem Schlüsselwechsel).
@interface MeshSealKey : NSObject
- (instancetype)initWithKey:(NSData *)key;   // nil, wenn key nicht 32 Byte hat
- (void)wipe;
@end

@interface MeshSeal : NSObject
+ (NSString *)seal:(NSString *)plain key:(NSData *)key context:(NSString *)context;   // nil ohne Schlüssel
+ (NSString *)open:(NSString *)sealed key:(NSData *)key context:(NSString *)context;  // nil bei Manipulation
+ (BOOL)isSealed:(NSString *)value;                                                   // enc2
// Dasselbe mit vorab abgeleiteten Teilschlüsseln (gleiches Format, gleicher MAC)
+ (NSString *)seal:(NSString *)plain sealKey:(MeshSealKey *)key context:(NSString *)context;
+ (NSString *)open:(NSString *)sealed sealKey:(MeshSealKey *)key context:(NSString *)context;

+ (NSString *)openLegacy:(NSString *)sealed key:(NSData *)key;                        // enc1, nur Migration
+ (BOOL)isLegacySealed:(NSString *)value;
@end
