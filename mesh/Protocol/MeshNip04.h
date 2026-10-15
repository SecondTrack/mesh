// Verschlüsselte Direktnachrichten nach NIP-04 (kind 4).
// content = base64(AES-256-CBC(text)) + "?iv=" + base64(iv), Schlüssel = ECDH-Shared-X.
// NIP-04 verbirgt keine Metadaten (Absender, Empfänger, Zeit sind sichtbar). Der Nachfolger NIP-44
// kommt erst zusammen mit der Android-App, sonst könnten beide nicht mehr miteinander reden.
#import <Foundation/Foundation.h>
@class MeshKeys;

@interface MeshNip04 : NSObject
// Klartext -> "<base64ct>?iv=<base64iv>". nil bei Fehler.
+ (NSString *)encrypt:(NSString *)text keys:(MeshKeys *)keys peerXonlyPub:(NSData *)peer32;
// "<base64ct>?iv=<base64iv>" -> Klartext. nil bei Fehler/ungültigem Format.
+ (NSString *)decrypt:(NSString *)payload keys:(MeshKeys *)keys peerXonlyPub:(NSData *)peer32;
// Dasselbe mit dem schon berechneten ECDH-Geheimnis (32 Byte, ecdhSharedX), z.B. je Kontakt zwischengespeichert.
+ (NSString *)encrypt:(NSString *)text sharedX:(NSData *)key;
+ (NSString *)decrypt:(NSString *)payload sharedX:(NSData *)key;
@end
