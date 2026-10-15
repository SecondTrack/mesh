// Team-Chat "Mesh Team" (docs/TEAM_GROUPS_PROTOCOL.md, Teil A) einer Identität:
//  - Rundbriefe "an alle": kind 1 von MeshTeamPubkey mit Tag t=mesh-team.
//  - Anonyme Antworten: kind-4-DMs (nur NIP-44) mit einem Einweg-Schlüssel E, nie aus der Identität
//    abgeleitet, versiegelt gespeichert. Alles für E läuft über einen eigenen Relay-Pool auf eigenen
//    Tor-Kreisen (SOCKS-Zugangsdaten, IsolateSOCKSAuth); über ihn laufen auch die Rundbriefe. Ohne Tor
//    wird dafür nichts gesendet oder abonniert. Er verbindet (auch neu) immer erst nach einer eigenen
//    Zufallspause (5–60 s, MeshRelayPool jitter), damit die Verbindungen nie gleichzeitig aufgehen.
// Steht MeshTeamPubkey auf dem Platzhalter (64 Nullen) oder ist die Identität selbst das Team, gibt
// es keinen Team-Chat und keinen Netzverkehr dafür.
#import <Foundation/Foundation.h>
@class MeshStore, MeshEvent, MeshMessage, MeshTeam;

extern NSString *const MeshTeamPubkey;   // TEAM_PK: einzige Stelle, Platzhalter = aus
extern NSString *const MeshTeamCard;     // TEAM_CARD: Mesh-Code "mesh:<npub>[?sig=…]", leer = keine Karte

@protocol MeshTeamDelegate <NSObject>
- (void)teamChanged:(MeshTeam *)team;                                // Verlauf geändert (neu laden)
- (void)team:(MeshTeam *)team received:(MeshMessage *)message;       // neu eingegangen (Hinweis)
@end

@interface MeshTeam : NSObject
+ (BOOL)isPlaceholder:(NSString *)teamPubkey;
// nil, wenn der Team-Chat für diese Identität aus ist. teamPubkey/card für Tests, sonst die Konstanten.
+ (instancetype)teamWithStore:(MeshStore *)store myPubkey:(NSString *)me;
- (instancetype)initWithStore:(MeshStore *)store myPubkey:(NSString *)me teamPubkey:(NSString *)teamPubkey card:(NSString *)card;

@property (nonatomic, mesh_weak) id<MeshTeamDelegate> delegate;
@property (nonatomic, readonly) NSString *teamPubkey;
@property (nonatomic, readonly) BOOL isolationAvailable;   // Tor vorhanden: E darf senden

- (void)startWithRelays:(NSArray *)urls;   // Begrüßung anlegen, E laden, ggf. getrennten Pool starten (urls nil: ohne Netz)
- (void)lock;                              // E aus dem RAM, Pool trennen

// Abo der Rundbriefe und deren Empfang (kind 1 und 5 von MeshTeamPubkey), über die getrennte Verbindung.
- (NSDictionary *)broadcastFilter;
- (BOOL)receiveBroadcast:(MeshEvent *)event;   // YES = Verlauf geändert

// Anonym schreiben (Text, höchstens 4000 Zeichen). nil ohne getrennte Verbindung oder bei Fehler.
- (MeshMessage *)send:(NSString *)text;
- (BOOL)receiveAnon:(MeshEvent *)event;        // vom getrennten Pool (und aus Tests)
- (NSString *)anonPubkey;                      // E (Hex), nil = noch keiner
- (MeshEvent *)lastSentEvent;                  // für Tests: zuletzt gebautes Event
- (void)startOver;                             // "Neu anfangen": persönliche Nachrichten weg, neuer E

@property (nonatomic) BOOL muted, hidden;      // gespeichert
@end
