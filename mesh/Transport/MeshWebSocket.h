// Minimaler RFC-6455-WebSocket-Client über MeshTLS (wss://).
// Blockierend; auf Hintergrund-Thread nutzen. Reicht für Nostr (Text-Frames JSON).
#import <Foundation/Foundation.h>

@interface MeshWebSocket : NSObject
@property (nonatomic, copy) NSString *socksCredential;   // eigener Tor-Kreis (siehe MeshTLS), vor connect setzen
// TLS + HTTP-Upgrade-Handshake. NO bei Fehler.
- (BOOL)connectHost:(NSString *)host port:(int)port path:(NSString *)path error:(NSString **)err;
// Ein Text-Frame senden (maskiert, wie vom Client verlangt).
- (BOOL)sendText:(NSString *)text;
// Nächste Text-Nachricht lesen; Control-Frames (ping/close) werden intern behandelt.
// nil bei Close/Fehler.
- (NSString *)readText;
- (void)close;
@end
