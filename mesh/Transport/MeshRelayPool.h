// Alle Relay-Verbindungen und die einzige Wiederverbindungs-Regel.
//
// Getrennte Relays werden mit wachsendem Abstand neu verbunden (5 s, 10 s, … bis 120 s),
// nach erfolgreicher Verbindung beginnt der Abstand wieder bei 5 s. Solange der Transport
// (Tor) nicht bereit ist, wird nicht verbunden. Alles auf dem Main-Thread.
#import <Foundation/Foundation.h>
#import "MeshRelay.h"

@class MeshEvent, MeshRelayPool;

// Was die Domäne vom Netz wissen muss. Einzelne Verbindungen bleiben im Pool.
@protocol MeshRelayPoolDelegate <NSObject>
// Abos für eine frische Verbindung (subId -> Filter). Nach einer NIP-42-Anmeldung erneut gesendet.
- (NSDictionary *)subscriptionsForPool:(MeshRelayPool *)pool;
// Eigene Events ohne Bestätigung: gehen an jede frisch verbundene Verbindung erneut hinaus.
- (NSArray *)pendingEventsForPool:(MeshRelayPool *)pool;
// NIP-42: signiertes kind-22242-Event für diese Challenge oder nil. Pro Verbindung fragt der Pool
// höchstens einmal, sonst schaukeln sich Anmeldung und Abonnement gegenseitig hoch.
- (MeshEvent *)pool:(MeshRelayPool *)pool authEventForRelay:(NSString *)url challenge:(NSString *)challenge;
- (void)pool:(MeshRelayPool *)pool didReceiveEvent:(MeshEvent *)event subId:(NSString *)subId;
// Ein Relay, an das das Event tatsächlich ging, hat es angenommen. Fremde OKs zählen nicht.
- (void)pool:(MeshRelayPool *)pool didStoreEvent:(NSString *)eventId;
@end

@interface MeshRelayPool : NSObject
- (instancetype)initWithURLs:(NSArray *)urls;

@property (nonatomic, mesh_weak) id<MeshRelayPoolDelegate> delegate;
@property (nonatomic, readonly) BOOL anyConnected;
@property (nonatomic, readonly) NSUInteger connectedCount;
@property (nonatomic, readonly) NSUInteger relayCount;
@property (nonatomic) NSTimeInterval timeUnit;   // Sekunden je Zeiteinheit, Standard 1; Tests verkürzen

- (void)start;   // verbinden und ab jetzt verbunden halten
- (void)stop;    // alle trennen, kein Wiederverbinden

// An alle gerade verbundenen Relays. Dauerhafte Abos liefert der Delegate bei jeder Verbindung.
- (void)publish:(MeshEvent *)event;
- (void)subscribe:(NSString *)subId filter:(NSDictionary *)filter;   // einmalig, ohne Wiederholung
- (void)resubscribe;
- (void)reconnectNow;  // Getrenntes sofort neu verbinden (z.B. im VoIP-Weckruf, Timer laufen dann nicht)   // Abos des Delegates neu senden (gleiche ID ersetzt das alte, NIP-01)
@end
