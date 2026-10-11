// Eigene Events, die noch kein Relay bestätigt hat. Bei jeder neuen Verbindung gehen sie erneut
// hinaus; nach der Frist gilt die Nachricht als nicht zugestellt. Versiegelt wie alle Inhalte.
#import "MeshStore.h"

@interface MeshStore (Outbox)
- (BOOL)queueEvent:(NSString *)json eventId:(NSString *)eventId created:(long long)created;
- (NSArray *)queuedEvents;                  // JSON-Strings, die 50 ältesten zuerst
- (BOOL)expireQueuedBefore:(long long)time; // Nachrichten als fehlgeschlagen markieren; YES = etwas geändert
@end
