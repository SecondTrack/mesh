// "Kontakt senden" wie in der Android-App: Liste der angenommenen Kontakte mit Bild und Name,
// Antippen schickt die Kontakt-Karte und kehrt zum Chat zurück.
#import <UIKit/UIKit.h>

@interface ContactPickerViewController : UIViewController
- (instancetype)initWithPeer:(NSString *)peerHex sent:(void (^)(void))sent;   // an wen; sent nach dem Senden
// Umgekehrt (Kontaktprofil "Kontakt teilen"): die Karte von contactHex an den gewählten Kontakt
- (instancetype)initSharingContact:(NSString *)contactHex;
// Allgemein: aus contacts wählen (z.B. Gruppen-Link senden, Kontakt vorschlagen). picked: YES = Seite schließen.
- (instancetype)initWithContacts:(NSArray *)contacts title:(NSString *)title picked:(BOOL (^)(NSString *pubkey))picked;
@end
