// Verschlüsselte Direktnachrichten nach NIP-44 v2 (wie die Android-App):
// ECDH (rohe X) -> HKDF-SHA256 "nip44-v2" = Gesprächsschlüssel; je Nachricht 32-Byte-Nonce ->
// ChaCha20 + HMAC-SHA256, Klartext auf Stufen gepolstert.
// payload = base64(0x02 ‖ nonce ‖ chiffrat ‖ mac). Anders als NIP-04 authentifiziert, aber ohne
// Forward Secrecy. Klartext höchstens 65535 Byte; Größeres geht über Signal oder NIP-04.
#import <Foundation/Foundation.h>
@class MeshKeys;

enum { MeshNip44MaxPlaintext = 65535 };

@interface MeshNip44 : NSObject
+ (NSString *)encrypt:(NSString *)text keys:(MeshKeys *)keys peerXonlyPub:(NSData *)peer32;
+ (NSString *)decrypt:(NSString *)payload keys:(MeshKeys *)keys peerXonlyPub:(NSData *)peer32;

// Kern mit festem Gesprächsschlüssel (und für die Testvektoren fester Nonce).
+ (NSData *)conversationKeyWithKeys:(MeshKeys *)keys peerXonlyPub:(NSData *)peer32;
+ (NSData *)conversationKeyFromSharedX:(NSData *)sharedX;
+ (NSString *)encrypt:(NSString *)text conversationKey:(NSData *)key nonce:(NSData *)nonce;
+ (NSString *)decrypt:(NSString *)payload conversationKey:(NSData *)key;
+ (NSUInteger)paddedLength:(NSUInteger)length;
@end
