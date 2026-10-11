// Entscheidet, ob eine eingehende Nachricht gespeichert wird, und schafft bei Fremden Platz.
// Fremde (nicht angenommene Kontakte) sind begrenzt: Anzahl, Nachrichten und Bytes je Fremdem und
// Bytes aller Fremden zusammen. Am Limit wird der älteste Fremde verdrängt, damit Wegwerf-
// Schlüssel keinen echten Erstkontakt aussperren können.
#import <Foundation/Foundation.h>
@class MeshStore;

extern const int MeshMaxStrangers;
extern const int MeshMaxStrangerMessages;          // je Fremdem
extern const long long MeshMaxStrangerBytes;       // je Fremdem
extern const long long MeshMaxAllStrangerBytes;    // alle Fremden zusammen
extern const int MeshMaxTombstones;                // Löschmerker; ältere Events schickt das DM-Abo (since) nicht mehr

@interface MeshInboxPolicy : NSObject
- (instancetype)initWithStore:(MeshStore *)store;
// YES = speichern. Legt einen unbekannten Absender als nicht angenommenen Kontakt an.
- (BOOL)admitFrom:(NSString *)pubkey eventId:(NSString *)eventId bytes:(long long)bytes;
@end
