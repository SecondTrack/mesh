// Eigene Events, die noch kein Relay bestätigt hat. Bei jeder neuen Verbindung gehen sie erneut
// hinaus; nach der Frist gilt die Nachricht als nicht zugestellt. Versiegelt wie alle Inhalte.
#import "MeshStore.h"

@interface MeshStore (Outbox)
- (BOOL)queueEvent:(NSString *)json eventId:(NSString *)eventId created:(long long)created;
enum { MeshOutboxMaxBytes = 4 * 1024 * 1024 };   // je Verbindung höchstens so viel aus der Warteschlange

- (NSArray *)queuedEvents;                  // JSON-Strings, die ältesten zuerst (höchstens 50 und MeshOutboxMaxBytes)
// Dasselbe ohne die genannten Event-IDs (schon an dieses Relay gegangen), höchstens maxBytes (mindestens eins).
- (NSArray *)queuedEventsExcluding:(NSSet *)eventIds maxBytes:(NSUInteger)maxBytes;
- (BOOL)expireQueuedBefore:(long long)time; // Nachrichten als fehlgeschlagen markieren; YES = etwas geändert

// Gruppen-Fan-out (dauerhaft, übersteht Sperren): jede Kopie einer Gruppennachricht gehört zur Nachricht.
// Wird die Nachricht gelöscht (jeder Weg), verlassen alle Kopien die Warteschlange (Trigger im Schema).
- (BOOL)addFanout:(NSString *)eventId message:(long long)rowId;
- (BOOL)markFanoutDelivered:(NSString *)eventId;   // YES = Status der Nachricht geändert
- (BOOL)hasMessageRow:(long long)rowId;
- (void)dropQueuedCopiesInChat:(NSString *)chat;   // Gruppe verlassen: Unbestätigtes nicht mehr senden
@end
