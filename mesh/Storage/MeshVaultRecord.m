#import "MeshVaultRecord.h"

@implementation MeshVaultRecord

- (BOOL)isEqualToRecord:(MeshVaultRecord *)other {
    return other && [other.salt isEqualToData:_salt] && [other.iv isEqualToData:_iv]
        && [other.ciphertext isEqualToData:_ciphertext] && [other.pubkey isEqualToString:_pubkey]
        && other.iterations == _iterations && other.boundToDevice == _boundToDevice && other.kdf == _kdf;
}

@end
