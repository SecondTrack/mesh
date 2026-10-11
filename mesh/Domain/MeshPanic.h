// Notlöschung wie in der Android-App (PanicStore.kt). Zwei Auslöser, gespeichert nur als Ableitung:
//
//  - Codewort: Ein Kontakt schickt ein Event mit Tag ["mw", <Token>]; das Token ist
//    "p2:" + hex(PBKDF2-HMAC-SHA256(Codewort, "mesh:panic:v2:" + Ziel-Pubkey, 120000, 32)). Es lässt
//    sich ohne Schlüssel prüfen, wirkt also auch gesperrt. Eine Textnachricht mit genau dem
//    Codewort löst ebenfalls aus (nur im entsperrten Zustand lesbar).
//  - Panik-PIN: am Sperrbildschirm statt der echten PIN eingegeben, löscht sie alles. Gespeichert
//    ist nur ein Prüfwert aus PBKDF2 mit dem Gerätegeheimnis, so teuer wie die echte PIN.
//
// Gespeichert im Schlüsselbund: die Token auch bei gesperrtem Gerät lesbar, die Panik-PIN nur entsperrt.
#import <Foundation/Foundation.h>

@protocol MeshPanicStorage <NSObject>
- (NSData *)panicDataNamed:(NSString *)name;
- (BOOL)setPanicData:(NSData *)data named:(NSString *)name;   // nil = löschen
@end

@interface MeshPanic : NSObject
- (instancetype)init;                                          // Schlüsselbund
- (instancetype)initWithStorage:(id<MeshPanicStorage>)storage;  // Tests

+ (NSString *)triggerFor:(NSString *)codeword target:(NSString *)pubkeyHex;   // das Token für ["mw", …]

// Codewort für alle eigenen Identitäten (ein Token je Pubkey); leer = ausschalten.
- (BOOL)setCodeword:(NSString *)codeword pubkeys:(NSArray *)pubkeys;
- (BOOL)hasCodeword;
- (NSUInteger)codewordIdentities;   // für wie viele Identitäten Token gespeichert sind
- (BOOL)matchesTrigger:(NSString *)tagValue;                    // Wert eines "mw"-Tags
- (BOOL)matchesTrigger:(NSString *)tagValue sentAt:(long long)createdAt;   // und nicht älter als das Codewort
- (BOOL)matchesText:(NSString *)text myPubkey:(NSString *)pubkeyHex;

// Panik-PIN; deviceSecret wie beim Vault (32 Byte).
- (BOOL)setPin:(NSString *)pin deviceSecret:(NSData *)secret;
- (BOOL)hasPin;
- (BOOL)matchesPin:(NSString *)pin deviceSecret:(NSData *)secret;
- (void)clearPin;

- (void)clearAll;
@end
