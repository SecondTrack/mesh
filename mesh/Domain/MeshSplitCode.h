// MeshSplitCode.h (Domain) — Kontakt-Code auf mehrere QR-Codes verteilen (nur iPod ↔ iPod).
// Der volle Code (mesh:<npub>?sig=<Paket>) ist für alte Kameras zu dicht. Geteilt trägt jeder Teil nur
// einen Bruchteil: "meshp:<n>/<k>:<id>:<stück>". id = Prüfwert des ganzen Codes, damit nur zusammengehörige
// Teile verbunden werden (der Code wechselt alle 10 s). Android kennt das Format nicht – dort den vollen Code zeigen.
#import <Foundation/Foundation.h>

#define MESH_SPLIT_PARTS 3

@interface MeshSplitCode : NSObject
+ (NSArray *)partsOf:(NSString *)code;          // MESH_SPLIT_PARTS Teile
+ (NSArray *)partsOf:(NSString *)code count:(NSUInteger)k;
+ (BOOL)isPart:(NSString *)s;
- (NSString *)add:(NSString *)part;             // fertiger Code, sobald alle Teile mit gleicher id da sind, sonst nil
@property (nonatomic, readonly) NSArray *missing;     // Nummern der noch fehlenden Teile des zuletzt gesehenen Codes
@property (nonatomic, readonly) NSInteger total;      // Anzahl Teile des zuletzt gesehenen Codes
@end
