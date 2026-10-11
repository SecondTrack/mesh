// Nachrichtenformat von libsignal (WhisperTextProtocol.proto, Version 3), wie es die
// Android-App über libsignal-protocol-java 2.8.1 schreibt und liest:
//
//   SignalMessage       = 0x33 ‖ Protobuf{1 ratchetKey, 2 counter, 3 previousCounter, 4 ciphertext} ‖ MAC[8]
//   PreKeySignalMessage = 0x33 ‖ Protobuf{1 preKeyId?, 2 baseKey, 3 identityKey, 4 message, 5 registrationId, 6 signedPreKeyId}
//
// MAC = HMAC-SHA256(macKey, Absender-Identität ‖ Empfänger-Identität ‖ Version ‖ Protobuf), gekürzt.
// Öffentliche Schlüssel stehen serialisiert mit 0x05 davor (33 Byte); hier sind sie roh (32 Byte).
#import <Foundation/Foundation.h>

@interface MeshSignalMessage : NSObject
+ (instancetype)messageWithRatchetKey:(NSData *)ratchetKey counter:(uint32_t)counter previousCounter:(uint32_t)previous
                           ciphertext:(NSData *)ciphertext macKey:(NSData *)macKey
                       senderIdentity:(NSData *)sender receiverIdentity:(NSData *)receiver;
+ (instancetype)parse:(NSData *)serialized;   // nil bei falscher Version oder unvollständig
- (BOOL)verifyMacKey:(NSData *)macKey senderIdentity:(NSData *)sender receiverIdentity:(NSData *)receiver;

@property (nonatomic, readonly) NSData *ratchetKey;      // 32 Byte
@property (nonatomic, readonly) uint32_t counter, previousCounter;
@property (nonatomic, readonly) NSData *ciphertext;
@property (nonatomic, readonly) NSData *serialized;
@end

@interface MeshPreKeySignalMessage : NSObject
+ (instancetype)messageWithRegistrationId:(uint32_t)registrationId preKeyId:(uint32_t)preKeyId
                           signedPreKeyId:(uint32_t)signedPreKeyId baseKey:(NSData *)baseKey
                              identityKey:(NSData *)identityKey message:(MeshSignalMessage *)message;
+ (instancetype)parse:(NSData *)serialized;

@property (nonatomic, readonly) uint32_t registrationId;
@property (nonatomic, readonly) uint32_t preKeyId;            // 0 = ohne Einmal-Schlüssel
@property (nonatomic, readonly) uint32_t signedPreKeyId;
@property (nonatomic, readonly) NSData *baseKey, *identityKey;   // je 32 Byte
@property (nonatomic, readonly) MeshSignalMessage *message;
@property (nonatomic, readonly) NSData *serialized;
@end

// 0x05 ‖ Schlüssel bzw. zurück; nil, wenn es kein Curve25519-Schlüssel ist.
NSData *MeshSignalSerializeKey(NSData *key32);
NSData *MeshSignalDeserializeKey(NSData *key33);
