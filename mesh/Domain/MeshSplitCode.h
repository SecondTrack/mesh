// MeshSplitCode.h (Domain) — Kontakt-Code auf zwei QR-Codes verteilen (nur iPod ↔ iPod).
// Der volle Code (mesh:<npub>?sig=<Paket>) ist für alte Kameras zu dicht. Geteilt trägt jeder Teil nur
// die Hälfte: "meshp:<n>/2:<id>:<stück>". id = Prüfwert des ganzen Codes, damit nur zusammengehörige
// Teile verbunden werden (der Code wechselt alle 10 s). Android kennt das Format nicht – dort den vollen Code zeigen.
#import <Foundation/Foundation.h>

@interface MeshSplitCode : NSObject
+ (NSArray *)partsOf:(NSString *)code;          // genau zwei Teile
+ (BOOL)isPart:(NSString *)s;
- (NSString *)add:(NSString *)part;             // fertiger Code, sobald beide Teile mit gleicher id da sind, sonst nil
@property (nonatomic, readonly) NSInteger lastPart;   // zuletzt erkannter Teil (1 oder 2), 0 = noch keiner
@end
