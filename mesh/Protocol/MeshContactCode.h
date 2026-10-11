// Kontakt-Code aus Eingabe, QR-Code oder Kontaktkarte, wie in der Android-App (MeshCode.kt):
//
//   mesh:<npub>[?node=<onion>&sig=<Signal-Bundle>]     Mesh-Code
//   nostr:<npub>, <npub>, 64 Hex-Zeichen              Nostr (NIP-19/NIP-21)
//
// Groß- und Kleinschreibung zählt nur im Bundle (Base64url); QR-Codes im alphanumerischen Modus
// liefern "NOSTR:NPUB1…". Die .onion (node=) braucht nur Androids Tor-Zustellung und wird übergangen.
#import <Foundation/Foundation.h>

@interface MeshContactCode : NSObject
+ (instancetype)parse:(NSString *)input;    // nil bei ungültigem Schlüssel oder über 1024 Zeichen
+ (NSString *)codeWithNpub:(NSString *)npub bundle:(NSString *)bundle;   // ohne .onion (nur Android hat eine)

@property (nonatomic, readonly) NSString *pubkey;   // x-only als Hex, klein
@property (nonatomic, readonly) NSString *bundle;   // Signal-Bundle (Base64url) oder nil
@end

NSString *MeshPubkeyFromContactInput(NSString *input);   // = [MeshContactCode parse:input].pubkey
