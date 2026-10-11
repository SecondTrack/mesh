// Eine Identität für den Umschalter: Nummer, Schlüssel, eigenes Profil.
#import <Foundation/Foundation.h>

@interface MeshIdentityInfo : NSObject
@property (nonatomic, assign) int slot;
@property (nonatomic, copy)   NSString *pubkey;    // nil, wenn sie sich nicht entsperren ließ
@property (nonatomic, copy)   NSString *name;
@property (nonatomic, copy)   NSString *picture;
@property (nonatomic, assign) BOOL active;
@end
