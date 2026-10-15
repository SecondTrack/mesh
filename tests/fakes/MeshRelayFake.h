// Zusätzliche Schnittstelle des Schein-Relays für Tests.
#import "MeshRelay.h"

@interface MeshRelay (Fake)
- (int)connectCalls;
- (int)sent;
- (void)fakeUp;     // Verbindung steht
- (void)fakeDrop;   // bestehende Verbindung bricht ab
- (void)fakeFail;   // Verbindungsaufbau scheitert
- (void)fakeOK:(NSString *)eventId;
- (void)fakeAuth;   // Relay verlangt NIP-42-Anmeldung
- (void)fakeWrite;  // Schreib-Warteschlange abgearbeitet (relayDidDrain:, wenn etwas abgelehnt war)
- (int)refused;     // wegen voller Warteschlange abgelehnte Events
- (NSArray *)published;   // Event-IDs dieser Verbindung
@end
