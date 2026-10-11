#import "MeshInboxPolicy.h"
#import "MeshStore.h"

const int MeshMaxStrangers = 50;
const int MeshMaxStrangerMessages = 100;
const long long MeshMaxStrangerBytes = 5 * 1024 * 1024;
const long long MeshMaxAllStrangerBytes = 20 * 1024 * 1024;
const int MeshMaxTombstones = 5000;

@implementation MeshInboxPolicy {
    MeshStore *_store;
}

- (instancetype)initWithStore:(MeshStore *)store {
    if ((self = [super init])) _store = store;
    return self;
}

- (BOOL)admitFrom:(NSString *)pubkey eventId:(NSString *)eventId bytes:(long long)bytes {
    // Vom Nutzer gelöscht oder blockiert: nicht einmal den Kontakt wieder anlegen.
    if ([_store isDeleted:eventId] || [_store isBlocked:pubkey]) return NO;
    if ([_store isAccepted:pubkey]) return YES;

    if ([_store isContact:pubkey]) {
        long long own = 0;
        int count = [_store receivedCount:pubkey bytes:&own];
        return count < MeshMaxStrangerMessages && own + bytes <= MeshMaxStrangerBytes
            && [_store unacceptedBytes] + bytes <= MeshMaxAllStrangerBytes;
    }

    if (bytes > MeshMaxStrangerBytes) return NO;
    while ([_store unacceptedContactCount] >= MeshMaxStrangers
           || [_store unacceptedBytes] + bytes > MeshMaxAllStrangerBytes) {
        NSString *oldest = [_store oldestUnacceptedContact];
        if (!oldest || ![_store deleteContact:oldest]) return NO;   // kein Platz zu schaffen
        [_store pruneTombstonesKeeping:MeshMaxTombstones];   // Wegwerf-Schlüssel füllen sonst die Merker
    }
    [_store upsertContact:pubkey name:@"" accepted:NO];
    return YES;
}

@end
