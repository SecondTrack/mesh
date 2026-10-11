// Passphrasen aus zufälligen Wörtern (Diceware), je 7776 Wörter, also log2(7776) ≈ 12,9 Bit je Wort:
//   de  Liste de-7776 von dys2p (CC0), Resources/wordlist-de.txt
//   en  EFF Large Wordlist (CC BY 3.0, Electronic Frontier Foundation), Resources/wordlist-en.txt;
//       geändert: Bindestriche entfernt (dropdown, felttip, tshirt), yo-yo durch yolk ersetzt, weil
//       yoyo sonst doppelt wäre und die Eingabe Satzzeichen ignoriert.
// Gewürfelt wird mit SecRandom; selbst gewählte Sätze sind viel leichter zu erraten und werden nicht
// angeboten. Entsperren braucht keine Liste (nur normalize:), die Sprache wird daher nicht gespeichert.
#import <Foundation/Foundation.h>

enum { MeshPassphraseWords = 5, MeshPassphraseStrongWords = 6 };

@interface MeshPassphrase : NSObject
+ (NSArray *)languages;                                  // @[@"de", @"en"]
+ (NSString *)defaultLanguage;                           // Sprache der App, sonst en
+ (NSArray *)wordListForLanguage:(NSString *)language;   // 7776 verschiedene Wörter oder nil
+ (void)setWordListDirectory:(NSString *)directory;      // Tests (sonst das App-Bundle)
+ (NSArray *)randomWords:(NSUInteger)count language:(NSString *)language;
+ (NSString *)normalize:(NSString *)input;               // klein, nur Buchstaben, ein Leerzeichen zwischen Wörtern
+ (NSUInteger)knownWordsIn:(NSString *)normalized;       // wie viele Wörter aus einer der Listen stammen
+ (double)bitsForWords:(NSUInteger)count;
@end
