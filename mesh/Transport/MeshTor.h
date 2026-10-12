// Tor-Transport: Relays werden über Tors SOCKS5-Proxy (127.0.0.1:19050) erreicht, sie sehen dann
// nur einen Tor-Ausgang statt der IP des Geräts. Kein eigener Hidden Service.
//
// Tor läuft nicht in der App, sondern als LaunchDaemon de.mesh.tor (vendor/tor/mesh-tor, Benutzer
// mobile, siehe layout/). In der App würde iOS es beim Wechsel in den Hintergrund einfrieren; so
// liefert der Dienst weiter Daten an die VoIP-markierten Sockets und weckt die App.
// Die App fragt über den Steuer-Socket (Unix-Socket im Datenordner, Cookie von dort) den Fortschritt
// ab und prüft, dass Tor selbst den SOCKS-Port hält. Ist Tor aktiv, aber nicht bereit, verbindet Mesh gar nicht (siehe MeshRelayPool, MeshTLS).
// Nur mit -DMESH_USE_TOR=1.
#import <Foundation/Foundation.h>

typedef enum { MeshTorOff = 0, MeshTorStarting, MeshTorReady, MeshTorFailed } MeshTorState;

@interface MeshTor : NSObject
+ (instancetype)shared;

@property (nonatomic, readonly) MeshTorState state;
@property (nonatomic, readonly) int bootstrapPercent;   // 0..100
@property (nonatomic, readonly) BOOL enabled;           // MESH_USE_TOR

// 0 wenn Tor aus/nicht bereit, dann verbindet MeshTLS direkt (nur ohne Tor); sonst 19050.
@property (nonatomic, readonly) int socksPort;

- (BOOL)hasDirectoryCache;   // Netz-Verzeichnis schon da? Ohne (erster Start) lädt Tor es erst herunter – das dauert am iPod Minuten
- (void)forgetState;   // Tor beenden und seinen Zustand (Guards, letzte Nutzung) löschen; startet danach neu
- (void)start;   // ohne Wirkung, wenn deaktiviert; sonst den Dienst beobachten (eigener Thread)
@end
