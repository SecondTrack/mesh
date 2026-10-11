// Signal-Bundle im Format der Android-App (MeshSignal.kt), Base64url ohne Auffüllung:
//
//   regId(4) ‖ signedPreKeyId(4) ‖ Identität(33) ‖ signierter PreKey(33) ‖ Signatur(64)
//   [‖ Einmal-PreKey-ID(4) ‖ Einmal-PreKey(33)]
//
// Zahlen big-endian, Schlüssel mit 0x05 davor. Reist im Kontakt-QR (sig=) oder verschlüsselt in
// Nachrichten (\1mesh:mb:). Mit Einmal-PreKey hat schon die erste Nachricht Forward Secrecy.
#import <Foundation/Foundation.h>

@interface MeshSignalBundle : NSObject
+ (instancetype)parse:(NSString *)base64url;   // nil bei falscher Länge oder ungültigen Schlüsseln
+ (NSString *)encodeRegistrationId:(uint32_t)registrationId signedPreKeyId:(uint32_t)signedPreKeyId
                          identity:(NSData *)identity signedPreKey:(NSData *)signedPreKey signature:(NSData *)signature
                         oneTimeId:(uint32_t)oneTimeId oneTimeKey:(NSData *)oneTimeKey;   // oneTimeKey nil = ohne

@property (nonatomic, readonly) uint32_t registrationId, signedPreKeyId, oneTimeId;
@property (nonatomic, readonly) NSData *identity, *signedPreKey, *signature, *oneTimeKey;   // Schlüssel roh, 32 Byte
- (BOOL)signatureValid;   // Identität hat den PreKey signiert (wie SessionBuilder.process)
@end

NSString *MeshBase64URLEncode(NSData *data);   // ohne '='
NSData *MeshBase64URLDecode(NSString *string);
