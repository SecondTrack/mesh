// Was über einzelne Nachrichten hinausgeht: Reaktionen, Löschen auf Anweisung des Gegenübers,
// Chat leeren, Selbstlösch-Timer je Chat und das Wegräumen abgelaufener Nachrichten.
#import "MeshStore.h"

@interface MeshStore (Chat)
// Reaktion auf die Nachricht mit cmid/Event-ID key im Chat; emoji nil oder leer entfernt sie.
// mine: meine Reaktion, sonst die des Kontakts. YES, wenn es die Nachricht gibt.
- (BOOL)setReaction:(NSString *)emoji mine:(BOOL)mine key:(NSString *)key chat:(NSString *)chat;

// Steueranweisung (Reaktion, Löschen, Leeren, Timer) verarbeitet: wie ein Tombstone, damit ein
// Relay sie nicht noch einmal anwenden lässt.
- (void)rememberProcessed:(NSString *)eventId;

// "Für alle löschen" vom Kontakt: nur seine eigenen Nachrichten in diesem Chat.
- (BOOL)deletePeerMessageWithKey:(NSString *)key chat:(NSString *)chat;

// Alle Nachrichten des Chats löschen (+ Tombstones); spätere Events mit älterem Zeitstempel
// bleiben draußen (clearedAt). Der Kontakt bleibt.
- (BOOL)clearChat:(NSString *)chat at:(long long)time;
- (long long)clearedAt:(NSString *)chat;

// Selbstlöschen für neue Nachrichten im Chat: Sekunden (0 = aus), fromSent: Uhr ab dem Absenden
// statt ab dem Lesen.
- (int)timerForChat:(NSString *)chat fromSent:(BOOL *)fromSent;
- (void)setTimer:(int)seconds fromSent:(BOOL)fromSent chat:(NSString *)chat;

// Empfangene Nachrichten mit Timer gelten beim Öffnen des Chats als gelesen: Uhr starten.
- (void)startTimersInChat:(NSString *)chat now:(long long)now;
// Bis wann der Chat gelesen ist (Unix-Sekunden, 0 = nie geöffnet seit dem Update).
- (long long)readAtForChat:(NSString *)chat;
- (void)setReadAt:(long long)time chat:(NSString *)chat;

// Abgelaufene Nachrichten löschen (+ Tombstones). Anzahl der gelöschten.
- (int)deleteExpiredAt:(long long)now;
- (long long)nextExpiry;   // frühester Ablauf, 0 = keiner
@end
