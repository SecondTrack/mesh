// Sicherheits-Code als QR zum Scannen, statt 60 Ziffern vorzulesen (wie Signal). Gleiches Format wie Android:
//   meshsn:1:<Pubkey des Zeigenden>:<Pubkey dessen, der scannt>:<60 Ziffern>
// Die beiden Pubkeys binden den Code an genau dieses Paar: ein Code aus einem anderen Chat passt nicht.
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, MeshSafetyScan) {
    MeshSafetyMatch,          // stimmt: niemand dazwischen
    MeshSafetyMismatch,       // gleiches Paar, andere Ziffern: jemand sitzt dazwischen (oder falscher Kontakt)
    MeshSafetyOtherContact,   // Code eines anderen Paares (anderer Chat, eigener Code)
    MeshSafetyNotACode
};

@interface MeshSafetyCode : NSObject
// groups: 12 Gruppen wie von MeshSession safetyNumberWith:
+ (NSString *)payloadFrom:(NSString *)myPubkeyHex to:(NSString *)peerPubkeyHex groups:(NSArray *)groups;
+ (MeshSafetyScan)check:(NSString *)scanned me:(NSString *)myPubkeyHex peer:(NSString *)peerPubkeyHex groups:(NSArray *)groups;
@end
