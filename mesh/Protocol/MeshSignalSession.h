// Signal-Sitzung mit einem Kontakt: X3DH zum Aufbau, danach Double Ratchet, wie libsignal
// (RatchetingSession, SessionCipher, SessionRecord). Kennt keinen Speicher: MeshSignal lädt die
// Sitzung, lässt sie ver- oder entschlüsseln und speichert sie wieder (als Property-List).
//
// Schlüsselableitung (HKDF-SHA256 nach RFC 5869):
//   X3DH:   0xFF×32 ‖ DH1 ‖ DH2 ‖ DH3 [‖ DH4]  --"WhisperText"-->     Root ‖ Kette
//   Ratchet: DH(neu)  mit Salz Root            --"WhisperRatchet"-->  Root ‖ Kette
//   Nachricht: HMAC(Kette, 0x01)               --"WhisperMessageKeys"--> AES ‖ MAC ‖ IV
//   nächste Kette: HMAC(Kette, 0x02)
#import <Foundation/Foundation.h>
@class MeshSignalMessage, MeshPreKeySignalMessage;

@interface MeshSignalKeyPair : NSObject
+ (instancetype)generate;
+ (instancetype)withPrivateKey:(NSData *)privateKey;   // öffentlicher wird berechnet
@property (nonatomic, readonly) NSData *privateKey, *publicKey;   // je 32 Byte
- (NSData *)agreeWith:(NSData *)publicKey;            // X25519; nil bei falscher Länge
- (NSData *)sign:(NSData *)message;                   // 64 Byte, wie Curve.calculateSignature
@end

BOOL MeshSignalVerify(NSData *publicKey, NSData *message, NSData *signature);

typedef NS_ENUM(NSInteger, MeshSignalDecryptError) {
    MeshSignalDecryptOK,
    MeshSignalDecryptDuplicate,   // schon entschlüsselt
    MeshSignalDecryptInvalid      // passt zu keinem Zustand
};

@interface MeshSignalSession : NSObject
// Alice: aus dem Bundle des Kontakts (Signatur schon geprüft). oneTime darf nil sein.
+ (instancetype)sessionWithOurIdentity:(MeshSignalKeyPair *)identity registrationId:(uint32_t)registrationId
                         theirIdentity:(NSData *)theirIdentity registrationId:(uint32_t)theirRegistrationId
                          signedPreKey:(NSData *)signedPreKey signedPreKeyId:(uint32_t)signedPreKeyId
                            oneTimeKey:(NSData *)oneTime oneTimeKeyId:(uint32_t)oneTimeId;

+ (instancetype)fromPropertyList:(NSData *)plist;
- (NSData *)propertyList;

@property (nonatomic, readonly) NSData *remoteIdentity;   // der aktuellen Sitzung

// Bob: Zustand aus einer PreKeySignalMessage aufbauen (der bisherige wird archiviert).
// NO, wenn diese Nachricht (Basisschlüssel) schon einen Zustand ergab: dann nur entschlüsseln.
- (BOOL)hasBaseKey:(NSData *)baseKey;
- (void)acceptPreKeyMessage:(MeshPreKeySignalMessage *)message ourIdentity:(MeshSignalKeyPair *)identity
             registrationId:(uint32_t)registrationId signedPreKey:(MeshSignalKeyPair *)signedPreKey
                 oneTimeKey:(MeshSignalKeyPair *)oneTime;
+ (instancetype)sessionFromPreKeyMessage:(MeshPreKeySignalMessage *)message ourIdentity:(MeshSignalKeyPair *)identity
                          registrationId:(uint32_t)registrationId signedPreKey:(MeshSignalKeyPair *)signedPreKey
                              oneTimeKey:(MeshSignalKeyPair *)oneTime;

// Verschlüsseln: PreKeySignalMessage, solange der Kontakt noch nicht geantwortet hat, sonst SignalMessage.
- (NSData *)encrypt:(NSData *)plaintext isPreKey:(BOOL *)isPreKey;
- (NSData *)decrypt:(MeshSignalMessage *)message error:(MeshSignalDecryptError *)error;
@end
